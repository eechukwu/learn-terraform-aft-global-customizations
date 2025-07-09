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

def lambda_handler(event, context):
    start_time = time.time()
    
    try:
        # Get regions from environment variable (set by Terraform locals)
        regions = event.get('regions', os.environ.get('TARGET_REGIONS', '').split(','))
        
        # Filter out empty strings and strip whitespace
        regions = [region.strip() for region in regions if region.strip()]
        
        # Fallback if no regions configured
        if not regions:
            logger.warning("No regions configured, using us-east-1 as fallback")
            regions = ['us-east-1']
        
        quota_value = event.get('quota_value', int(os.environ.get('QUOTA_VALUE', 200)))
        service_code = event.get('service_code', os.environ.get('SERVICE_CODE', 'vpc'))
        quota_code = event.get('quota_code', os.environ.get('QUOTA_CODE', 'L-0EA8095F'))
        action = event.get('action', 'request_quotas')
        
        logger.info(f"Processing {action} for regions: {regions}")
        
        results = {}
        
        with ThreadPoolExecutor(max_workers=min(len(regions), 10)) as executor:
            futures = {}
            
            for region in regions:
                if action == 'request_quotas':
                    future = executor.submit(request_quota_increase, service_code, quota_code, quota_value, region)
                elif action == 'check_status':
                    future = executor.submit(check_quota_status, service_code, quota_code, region)
                elif action == 'monitor_requests':
                    future = executor.submit(monitor_quota_requests, service_code, quota_code, region)
                else:
                    results[region] = {'status': 'error', 'error': f'Unknown action: {action}'}
                    continue
                futures[future] = region
            
            for future in as_completed(futures):
                region = futures[future]
                try:
                    results[region] = future.result(timeout=120)
                except Exception as e:
                    results[region] = {'status': 'error', 'error': str(e), 'region': region}
        
        if action == 'monitor_requests':
            approved = [r for r, result in results.items() if result.get('request_status') == 'CASE_CLOSED']
            pending = [r for r, result in results.items() if result.get('request_status') == 'PENDING']
            
            summary = {
                'total_regions': len(regions),
                'approved_regions': len(approved),
                'pending_regions': len(pending),
                'all_approved': len(pending) == 0,
                'execution_time_seconds': round(time.time() - start_time, 2)
            }
            
            if len(pending) == 0 and len(approved) > 0:
                send_completion_notification(results, summary)
        else:
            successful = [r for r, result in results.items() if result.get('status') in ['success', 'already_sufficient']]
            summary = {
                'total_regions': len(regions),
                'successful_regions': len(successful),
                'failed_regions': len(regions) - len(successful),
                'success_rate': f"{(len(successful)/len(regions)*100):.1f}%",
                'execution_time_seconds': round(time.time() - start_time, 2)
            }
        
        return {
            'statusCode': 200,
            'summary': summary,
            'results': results
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'execution_time_seconds': round(time.time() - start_time, 2)
        }

def request_quota_increase(service_code, quota_code, quota_value, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        
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

def check_quota_status(service_code, quota_code, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        current_quota = client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)
        
        return {
            'status': 'success',
            'current_value': int(current_quota['Quota']['Value']),
            'quota_name': current_quota['Quota']['QuotaName'],
            'region': region
        }
    except Exception as e:
        return {'status': 'error', 'error': str(e), 'region': region}

def monitor_quota_requests(service_code, quota_code, region):
    try:
        client = boto3.client('service-quotas', region_name=region, config=BOTO3_CONFIG)
        
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

def send_completion_notification(results, summary):
    try:
        sns = boto3.client('sns')
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        if not topic_arn:
            return
        
        message = f"""Quota Increase Requests Completed

All quota increase requests have been approved.

Summary:
- Total Regions: {summary['total_regions']}
- Approved Regions: {summary['approved_regions']}

Regional Results:
"""
        
        for region, result in results.items():
            if result.get('status') == 'success':
                message += f"- {region}: {result.get('current_value')} -> {result.get('requested_value')} (Approved)\n"
        
        sns.publish(
            TopicArn=topic_arn,
            Subject="AFT Quota Increases Approved",
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")