import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    AWS Lambda function for managing AWS service quotas
    """
    try:
        action = event.get('action', 'request_quotas')
        
        if action == 'request_quotas':
            return request_quotas()
        elif action == 'check_status':
            return check_quota_status()
        elif action == 'monitor_requests':
            return monitor_requests()
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def request_quotas():
    """
    Request quota increases for configured services
    """
    try:
        # Get configuration from environment variables
        target_regions = os.environ.get('TARGET_REGIONS', '').split(',')
        quota_config = parse_quota_config()
        
        results = {}
        total_requests = 0
        total_errors = 0
        
        for region in target_regions:
            region = region.strip()
            if not region:
                continue
                
            logger.info(f"Processing region: {region}")
            results[region] = {}
            
            # Create Service Quotas client for this region
            sq_client = boto3.client('servicequotas', region_name=region)
            
            for quota_name, quota_info in quota_config.items():
                try:
                    logger.info(f"Requesting quota increase for {quota_name} in {region}")
                    
                    # Check current quota
                    current_quota = get_current_quota(sq_client, quota_info['service_code'], quota_info['quota_code'])
                    
                    if current_quota >= quota_info['quota_value']:
                        logger.info(f"Quota {quota_name} already at or above target value in {region}")
                        results[region][quota_name] = {
                            'status': 'already_met',
                            'current_value': current_quota,
                            'target_value': quota_info['quota_value']
                        }
                        continue
                    
                    # Request quota increase
                    response = sq_client.request_service_quota_increase(
                        ServiceCode=quota_info['service_code'],
                        QuotaCode=quota_info['quota_code'],
                        DesiredValue=quota_info['quota_value']
                    )
                    
                    results[region][quota_name] = {
                        'status': 'requested',
                        'request_id': response['RequestedQuota']['Id'],
                        'current_value': current_quota,
                        'target_value': quota_info['quota_value'],
                        'description': quota_info['description']
                    }
                    
                    total_requests += 1
                    logger.info(f"Quota increase requested for {quota_name} in {region}")
                    
                except Exception as e:
                    logger.error(f"Error requesting quota for {quota_name} in {region}: {str(e)}")
                    results[region][quota_name] = {
                        'status': 'error',
                        'error': str(e)
                    }
                    total_errors += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quota requests processed',
                'results': results,
                'summary': {
                    'total_requests': total_requests,
                    'total_errors': total_errors
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in request_quotas: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_quota_status():
    """
    Check current quota status for all configured services
    """
    try:
        target_regions = os.environ.get('TARGET_REGIONS', '').split(',')
        quota_config = parse_quota_config()
        
        results = {}
        
        for region in target_regions:
            region = region.strip()
            if not region:
                continue
                
            results[region] = {}
            sq_client = boto3.client('servicequotas', region_name=region)
            
            for quota_name, quota_info in quota_config.items():
                try:
                    current_quota = get_current_quota(sq_client, quota_info['service_code'], quota_info['quota_code'])
                    
                    results[region][quota_name] = {
                        'current_value': current_quota,
                        'target_value': quota_info['quota_value'],
                        'status': 'met' if current_quota >= quota_info['quota_value'] else 'pending',
                        'description': quota_info['description']
                    }
                    
                except Exception as e:
                    logger.error(f"Error checking quota for {quota_name} in {region}: {str(e)}")
                    results[region][quota_name] = {
                        'status': 'error',
                        'error': str(e)
                    }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quota status checked',
                'results': results
            })
        }
        
    except Exception as e:
        logger.error(f"Error in check_quota_status: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def monitor_requests():
    """
    Monitor pending quota requests
    """
    try:
        target_regions = os.environ.get('TARGET_REGIONS', '').split(',')
        quota_config = parse_quota_config()
        
        results = {}
        pending_requests = 0
        
        for region in target_regions:
            region = region.strip()
            if not region:
                continue
                
            results[region] = {}
            sq_client = boto3.client('servicequotas', region_name=region)
            
            for quota_name, quota_info in quota_config.items():
                try:
                    # Get request history
                    response = sq_client.list_requested_service_quota_change_history(
                        ServiceCode=quota_info['service_code']
                    )
                    
                    # Find the most recent request for this quota
                    requests = [req for req in response['RequestedQuotas'] 
                              if req['QuotaCode'] == quota_info['quota_code']]
                    
                    if requests:
                        latest_request = max(requests, key=lambda x: x['Created'])
                        if latest_request['Status'] == 'PENDING':
                            pending_requests += 1
                            
                        results[region][quota_name] = {
                            'request_id': latest_request['Id'],
                            'status': latest_request['Status'],
                            'current_value': latest_request['CurrentValue'],
                            'desired_value': latest_request['DesiredValue'],
                            'created': latest_request['Created'].isoformat(),
                            'description': quota_info['description']
                        }
                    else:
                        results[region][quota_name] = {
                            'status': 'no_requests',
                            'description': quota_info['description']
                        }
                        
                except Exception as e:
                    logger.error(f"Error monitoring quota for {quota_name} in {region}: {str(e)}")
                    results[region][quota_name] = {
                        'status': 'error',
                        'error': str(e)
                    }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quota requests monitored',
                'results': results,
                'summary': {
                    'pending_requests': pending_requests
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in monitor_requests: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def parse_quota_config():
    """
    Parse quota configuration from environment variables
    """
    quota_config = {}
    
    # Parse environment variables to build quota configuration
    for key, value in os.environ.items():
        if key.startswith('QUOTA_CONFIG_'):
            # Parse key like QUOTA_CONFIG_SECURITY_GROUPS_SERVICE_CODE
            parts = key.replace('QUOTA_CONFIG_', '').split('_')
            if len(parts) >= 2:
                quota_name = '_'.join(parts[:-1]).lower()
                config_key = parts[-1].lower()
                
                if quota_name not in quota_config:
                    quota_config[quota_name] = {}
                
                quota_config[quota_name][config_key] = value
    
    return quota_config

def get_current_quota(sq_client, service_code, quota_code):
    """
    Get current quota value for a service
    """
    try:
        response = sq_client.get_service_quota(
            ServiceCode=service_code,
            QuotaCode=quota_code
        )
        return response['Quota']['Value']
    except Exception as e:
        logger.error(f"Error getting current quota: {str(e)}")
        return 0 