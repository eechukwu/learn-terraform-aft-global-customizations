import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    action = event.get('action', 'monitor_requests')
    
    try:
        if action == 'request_quotas':
            return request_quotas()
        elif action == 'monitor_requests':
            return monitor_requests()
        else:
            return {'statusCode': 400, 'body': json.dumps({'error': f'Unknown action: {action}'})}
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def request_quotas():
    target_regions = os.environ.get('TARGET_REGIONS', '').split(',')
    quota_config = json.loads(os.environ.get('QUOTA_CONFIG', '{}'))
    
    results = {}
    total_requests = 0
    
    for region in target_regions:
        region = region.strip()
        if not region:
            continue
            
        results[region] = {}
        sq_client = boto3.client('service-quotas', region_name=region)
        
        for quota_name, config in quota_config.items():
            try:
                current_quota = get_current_quota(sq_client, config['service_code'], config['quota_code'])
                
                if current_quota >= config['quota_value']:
                    results[region][quota_name] = {
                        'status': 'already_sufficient',
                        'current_value': current_quota,
                        'target_value': config['quota_value']
                    }
                    continue
                
                response = sq_client.request_service_quota_increase(
                    ServiceCode=config['service_code'],
                    QuotaCode=config['quota_code'],
                    DesiredValue=config['quota_value']
                )
                
                results[region][quota_name] = {
                    'status': 'requested',
                    'request_id': response['RequestedQuota']['Id'],
                    'current_value': current_quota,
                    'target_value': config['quota_value']
                }
                total_requests += 1
                
            except Exception as e:
                logger.error(f"Error with {quota_name} in {region}: {str(e)}")
                results[region][quota_name] = {'status': 'error', 'error': str(e)}
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {total_requests} quota requests',
            'results': results
        })
    }

def monitor_requests():
    target_regions = os.environ.get('TARGET_REGIONS', '').split(',')
    quota_config = json.loads(os.environ.get('QUOTA_CONFIG', '{}'))
    
    results = {}
    approved_requests = []
    
    for region in target_regions:
        region = region.strip()
        if not region:
            continue
            
        results[region] = {}
        sq_client = boto3.client('service-quotas', region_name=region)
        
        for quota_name, config in quota_config.items():
            try:
                response = sq_client.list_requested_service_quota_change_history(
                    ServiceCode=config['service_code']
                )
                
                requests = [req for req in response['RequestedQuotas'] 
                          if req['QuotaCode'] == config['quota_code']]
                
                if requests:
                    latest = max(requests, key=lambda x: x['Created'])
                    results[region][quota_name] = {
                        'status': latest['Status'].lower(),
                        'current_value': latest['CurrentValue'],
                        'requested_value': latest['DesiredValue']
                    }
                    
                    if latest['Status'] == 'APPROVED':
                        approved_requests.append({
                            'quota': quota_name,
                            'region': region,
                            'old_value': latest['CurrentValue'],
                            'new_value': latest['DesiredValue']
                        })
                else:
                    results[region][quota_name] = {'status': 'no_requests'}
                    
            except Exception as e:
                logger.error(f"Error checking {quota_name} in {region}: {str(e)}")
                results[region][quota_name] = {'status': 'error', 'error': str(e)}
    
    # Send notification only for approved quotas
    if approved_requests:
        send_approval_notification(approved_requests)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Monitoring complete',
            'results': results,
            'approved_count': len(approved_requests)
        })
    }

def get_current_quota(sq_client, service_code, quota_code):
    try:
        response = sq_client.get_service_quota(
            ServiceCode=service_code,
            QuotaCode=quota_code
        )
        return response['Quota']['Value']
    except Exception:
        return 0

def send_approval_notification(approved_requests):
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not sns_topic_arn:
        return
    
    try:
        sns_client = boto3.client('sns')
        
        message_lines = ["Quota increases approved:"]
        for req in approved_requests:
            message_lines.append(f"• {req['quota']} in {req['region']}: {req['old_value']} → {req['new_value']}")
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject="AWS Quota Increases Approved",
            Message="\n".join(message_lines)
        )
        
        logger.info(f"Sent approval notification for {len(approved_requests)} quotas")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")