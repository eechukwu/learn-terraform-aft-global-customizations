import json
import boto3
import os
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from botocore.config import Config
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BOTO3_CONFIG = Config(retries={'max_attempts': 5, 'mode': 'adaptive'})

def lambda_handler(event, context):
    start_time = time.time()
    
    try:
        regions = event.get('regions', ['us-east-1', 'us-west-2', 'eu-west-1', 'eu-west-2', 'ap-southeast-1'])
        quota_value = event.get('quota_value', int(os.environ.get('QUOTA_VALUE', 200)))
        service_code = event.get('service_code', os.environ.get('SERVICE_CODE', 'vpc'))
        quota_code = event.get('quota_code', os.environ.get('QUOTA_CODE', 'L-0EA8095F'))
        action = event.get('action', 'request_quotas')
        
        logger.info(f"Processing {len(regions)} regions for action: {action}")
        
        results = {}
        
        with ThreadPoolExecutor(max_workers=min(len(regions), 10)) as executor:
            futures = {}
            
            for region in regions:
                if action == 'request_quotas':
                    future = executor.submit(request_quota_increase, service_code, quota_code, quota_value, region)
                elif action == 'check_status':
                    future = executor.submit(check_quota_status, service_code, quota_code, region)
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
        
        successful = [r for r, result in results.items() if result.get('status') in ['success', 'already_sufficient']]
        execution_time = round(time.time() - start_time, 2)
        
        summary = {
            'total_regions': len(regions),
            'successful_regions': len(successful),
            'failed_regions': len(regions) - len(successful),
            'success_rate': f"{(len(successful)/len(regions)*100):.1f}%",
            'execution_time_seconds': execution_time
        }
        
        return {
            'statusCode': 200,
            'summary': summary,
            'results': results
        }
        
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
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