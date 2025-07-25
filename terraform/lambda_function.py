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
    regions = os.environ.get('TARGET_REGIONS', '').split(',')
    config = json.loads(os.environ.get('QUOTA_CONFIG', '{}'))
    
    results = {}
    requests_made = 0
    
    for region in regions:
        region = region.strip()
        if not region:
            continue
            
        results[region] = {}
        sq = boto3.client('service-quotas', region_name=region)
        
        for quota_name, quota_config in config.items():
            try:
                current = get_current_quota(sq, quota_config['service_code'], quota_config['quota_code'])
                
                if current >= quota_config['quota_value']:
                    results[region][quota_name] = {
                        'status': 'already_sufficient',
                        'current_value': current,
                        'target_value': quota_config['quota_value']
                    }
                    continue
                
                response = sq.request_service_quota_increase(
                    ServiceCode=quota_config['service_code'],
                    QuotaCode=quota_config['quota_code'],
                    DesiredValue=quota_config['quota_value']
                )
                
                results[region][quota_name] = {
                    'status': 'requested',
                    'request_id': response['RequestedQuota']['Id'],
                    'current_value': current,
                    'target_value': quota_config['quota_value']
                }
                requests_made += 1
                
            except Exception as e:
                logger.error(f"Error with {quota_name} in {region}: {str(e)}")
                results[region][quota_name] = {'status': 'error', 'error': str(e)}
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {requests_made} quota requests',
            'results': results
        })
    }

def monitor_requests():
    regions = os.environ.get('TARGET_REGIONS', '').split(',')
    config = json.loads(os.environ.get('QUOTA_CONFIG', '{}'))
    
    results = {}
    approved = []
    
    for region in regions:
        region = region.strip()
        if not region:
            continue
            
        results[region] = {}
        sq = boto3.client('service-quotas', region_name=region)
        
        for quota_name, quota_config in config.items():
            try:
                response = sq.list_requested_service_quota_change_history(
                    ServiceCode=quota_config['service_code']
                )
                
                requests = [req for req in response['RequestedQuotas'] 
                          if req['QuotaCode'] == quota_config['quota_code']]
                
                if requests:
                    latest = max(requests, key=lambda x: x['Created'])
                    results[region][quota_name] = {
                        'status': latest['Status'].lower(),
                        'current_value': latest['CurrentValue'],
                        'requested_value': latest['DesiredValue']
                    }
                    
                    if latest['Status'] == 'APPROVED':
                        approved.append({
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
    
    if approved:
        send_notification(approved)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Monitoring complete',
            'results': results,
            'approved_count': len(approved)
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

def send_notification(approved_requests):
    sns_topic = os.environ.get('SNS_TOPIC_ARN')
    if not sns_topic:
        return
    
    try:
        sns = boto3.client('sns')
        
        message = ["Quota increases approved:"]
        for req in approved_requests:
            message.append(f"• {req['quota']} in {req['region']}: {req['old_value']} → {req['new_value']}")
        
        sns.publish(
            TopicArn=sns_topic,
            Subject="AWS Quota Increases Approved",
            Message="\n".join(message)
        )
        
        logger.info(f"Sent notification for {len(approved_requests)} quotas")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")