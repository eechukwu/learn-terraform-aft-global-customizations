import json
import boto3
import os
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from botocore.config import Config
from botocore.exceptions import ClientError
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BOTO3_CONFIG = Config(retries={'max_attempts': 5, 'mode': 'adaptive'})

def get_all_quota_configs_from_env():
    quota_configs = {}
    for key, value in os.environ.items():
        if key.startswith('QUOTA_CONFIG_'):
            parts = key.replace('QUOTA_CONFIG_', '').split('_')
            if len(parts) >= 2:
                quota_name = '_'.join(parts[:-1]).lower()
                property_name = parts[-1].lower()
                if quota_name not in quota_configs:
                    quota_configs[quota_name] = {}
                if property_name == 'quota_value':
                    quota_configs[quota_name][property_name] = int(value)
                else:
                    quota_configs[quota_name][property_name] = value
    return quota_configs

def lambda_handler(event, context):
    start_time = time.time()
    try:
        regions = event.get('regions', os.environ.get('TARGET_REGIONS', '').split(','))
        regions = [r.strip() for r in regions if r.strip()]
        if not regions:
            logger.warning("No regions configured, using us-east-1 as fallback")
            regions = ['us-east-1']

        quota_configs = get_all_quota_configs_from_env()
        if not quota_configs:
            logger.error("No quota configurations found in environment variables")
            return {'statusCode': 500, 'error': 'No quota configurations found'}

        action = event.get('action', 'request_quotas')
        results = {}

        with ThreadPoolExecutor(max_workers=min(len(regions) * len(quota_configs), 20)) as executor:
            futures = {}
            for region in regions:
                for quota_type, config in quota_configs.items():
                    if action == 'request_quotas':
                        future = executor.submit(request_quota_increase, config, region)
                    elif action == 'check_status':
                        future = executor.submit(check_quota_status, config, region)
                    elif action == 'monitor_requests':
                        future = executor.submit(monitor_quota_requests, config, region)
                    elif action == 'service_status':
                        future = executor.submit(get_service_status, config, region)
                    else:
                        results[(region, quota_type)] = {'status': 'error', 'error': f'Unknown action: {action}'}
                        continue
                    futures[future] = (region, quota_type)

            for future in as_completed(futures):
                region, quota_type = futures[future]
                try:
                    results[(region, quota_type)] = future.result(timeout=120)
                except Exception as e:
                    results[(region, quota_type)] = {'status': 'error', 'error': str(e), 'region': region, 'quota_type': quota_type}

        summary = build_summary(results, action, regions, quota_configs)
        if action == 'monitor_requests' and summary.get('all_approved'):
            send_completion_notification(results, summary)

        output_results = {}
        for (region, quota_type), value in results.items():
            if region not in output_results:
                output_results[region] = {}
            output_results[region][quota_type] = value

        return {
            'statusCode': 200,
            'summary': summary,
            'results': output_results
        }
    except Exception as e:
        logger.error(f"Lambda handler error: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'execution_time_seconds': round(time.time() - start_time, 2)
        }

def request_quota_increase(config, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        service_code = config['service_code']
        quota_code = config['quota_code']
        quota_value = config['quota_value']
        current_quota = client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)
        current_value = int(current_quota['Quota']['Value'])
        if current_value >= quota_value:
            return {
                'status': 'already_sufficient',
                'current_value': current_value,
                'message': f'Current quota ({current_value}) already meets target ({quota_value})'
            }
        try:
            pending_requests = client.list_requested_service_quota_change_history(
                ServiceCode=service_code,
                Status='PENDING'
            )
            for request in pending_requests.get('RequestedQuotas', []):
                if request['QuotaCode'] == quota_code and request['DesiredValue'] >= quota_value:
                    return {
                        'status': 'already_pending',
                        'current_value': current_value,
                        'requested_value': int(request['DesiredValue']),
                        'request_id': request['Id'],
                        'message': f'Quota increase already pending'
                    }
        except ClientError:
            pass
        response = client.request_service_quota_increase(
            ServiceCode=service_code,
            QuotaCode=quota_code,
            DesiredValue=float(quota_value)
        )
        return {
            'status': 'success',
            'current_value': current_value,
            'requested_value': quota_value,
            'request_id': response['RequestedQuota']['Id'],
            'message': f'Quota increase requested from {current_value} to {quota_value}'
        }
    except ClientError as e:
        return {
            'status': 'error',
            'error': str(e),
            'error_code': e.response['Error']['Code']
        }
    except Exception as e:
        return {'status': 'error', 'error': str(e)}

def check_quota_status(config, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        service_code = config['service_code']
        quota_code = config['quota_code']
        current_quota = client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)
        return {
            'status': 'success',
            'current_value': int(current_quota['Quota']['Value']),
            'quota_name': current_quota['Quota']['QuotaName'],
            'region': region
        }
    except Exception as e:
        return {'status': 'error', 'error': str(e), 'region': region}

def monitor_quota_requests(config, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        service_code = config['service_code']
        quota_code = config['quota_code']
        current_quota = client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)
        current_value = int(current_quota['Quota']['Value'])
        requests = client.list_requested_service_quota_change_history(
            ServiceCode=service_code,
            QuotaCode=quota_code
        )
        latest_request = None
        for request in requests.get('RequestedQuotas', []):
            if not latest_request or request['Created'] > latest_request['Created']:
                latest_request = request
        if not latest_request:
            return {
                'status': 'no_requests',
                'current_value': current_value,
                'message': 'No quota increase requests found',
                'region': region
            }
        return {
            'status': 'success',
            'current_value': current_value,
            'requested_value': int(latest_request['DesiredValue']),
            'request_id': latest_request['Id'],
            'request_status': latest_request['Status'],
            'created': latest_request['Created'].strftime('%Y-%m-%d %H:%M:%S'),
            'last_updated': latest_request['LastUpdated'].strftime('%Y-%m-%d %H:%M:%S'),
            'message': f"Request {latest_request['Status']} - Current: {current_value}, Requested: {int(latest_request['DesiredValue'])}",
            'region': region
        }
    except Exception as e:
        return {'status': 'error', 'error': str(e), 'region': region}

def get_service_status(config, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        service_code = config['service_code']
        quota_code = config['quota_code']
        quota_value = config['quota_value']
        current_quota = client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)
        current_value = int(current_quota['Quota']['Value'])
        requests = client.list_requested_service_quota_change_history(
            ServiceCode=service_code,
            QuotaCode=quota_code
        )
        latest_request = None
        for request in requests.get('RequestedQuotas', []):
            if not latest_request or request['Created'] > latest_request['Created']:
                latest_request = request
        status = 'sufficient' if current_value >= quota_value else 'insufficient'
        info = {
            'service_name': config.get('description', ''),
            'current_value': current_value,
            'target_value': quota_value,
            'status': status
        }
        if latest_request:
            info.update({
                'has_request': True,
                'request_id': latest_request['Id'],
                'request_status': latest_request['Status'],
                'requested_value': int(latest_request['DesiredValue']),
                'request_created': latest_request['Created'].strftime('%Y-%m-%d %H:%M:%S'),
                'request_updated': latest_request['LastUpdated'].strftime('%Y-%m-%d %H:%M:%S')
            })
        else:
            info['has_request'] = False
        return info
    except Exception as e:
        return {'status': 'error', 'error': str(e), 'region': region}

def build_summary(results, action, regions, quota_configs):
    summary = {}
    summary['total_regions'] = int(len(regions))
    exec_time = float(round(time.time() - time.time(), 2))
    if action == 'monitor_requests':
        approved = [1 for v in results.values() if v.get('request_status') == 'CASE_CLOSED']
        pending = [1 for v in results.values() if v.get('request_status') == 'PENDING']
        summary['approved_regions'] = int(len(approved))
        summary['pending_regions'] = int(len(pending))
        summary['all_approved'] = bool(len(pending) == 0 and len(approved) > 0)
        summary['execution_time_seconds'] = exec_time
    elif action == 'service_status':
        summary['execution_time_seconds'] = exec_time
    else:
        successful = [1 for v in results.values() if v.get('status') in ['success', 'already_sufficient']]
        summary['successful_regions'] = int(len(successful))
        summary['failed_regions'] = int(len(results) - len(successful))
        summary['success_rate'] = f"{(len(successful)/len(results)*100):.1f}%"
        summary['execution_time_seconds'] = exec_time
    return summary

def send_completion_notification(results, summary):
    try:
        sns = boto3.client('sns')
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not topic_arn:
            return
        message = f"Quota Increase Requests Completed\n\nAll quota increase requests have been approved.\n\nSummary:\n- Total Regions: {summary.get('total_regions')}\n- Approved Regions: {summary.get('approved_regions')}\n\nRegional Results:\n"
        for (region, quota_type), result in results.items():
            if result.get('status') == 'success':
                message += f"- {region} ({quota_type}): {result.get('current_value')} -> {result.get('requested_value')} (Approved)\n"
        sns.publish(
            TopicArn=topic_arn,
            Subject="AFT Quota Increases Approved",
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}") 