# AFT Quota Manager

Automatically requests AWS service quota increases when new accounts are created through AFT.

## What This Does

When AFT creates a new AWS account, this system automatically requests quota increases for common services like Security Groups, Elastic IPs, IAM Roles, Lambda Functions, VPC Peering connections, and more. This prevents quota-related deployment issues and ensures your applications can scale properly from day one.

## Current Setup

### Resources
- Lambda function handles quota requests and monitoring
- SNS notifications to Slack via company modules
- CloudWatch Events checks quota status every 10 minutes
- Encrypted logs and DLQ for error handling

### Quotas Being Managed
- **Security Groups**: Increased to 200 per VPC
- **Elastic IPs**: Increased to 20 per region

### Regions Covered
- us-east-1
- us-west-2
- eu-west-1
- eu-west-2
- ap-southeast-1

*Additional regions can be added by editing the `target_regions` list in `terraform/locals.tf`*

## How It Works

1. AFT deploys this when you commit changes
2. Lambda immediately requests quota increases for all regions
3. System checks every 10 minutes if quotas are approved
4. Slack notifications sent when quotas are approved
5. Everything logged to CloudWatch

## Adding New Quotas

Edit `terraform/locals.tf` and add to the `quota_config`:

```hcl
iam_roles = {
  service_code = "iam"
  quota_code   = "L-FE177D2D"
  quota_value  = 5000
  description  = "IAM Roles per account"
}
```

Find quota codes in the AWS Service Quotas console.

## Configuration

The main settings are in `terraform/locals.tf`:

- `target_regions` - which regions to monitor
- `quota_config` - which quotas to request
- `common_tags` - tags applied to all resources

Slack notifications are configured in `terraform/variables.tf`:

- `slack_channel_name` - where notifications go
- `cloud_services_slack_topic_arn` - company Slack topic

## File Structure

```
├── api_helpers/
│   ├── pre-api-helpers.sh    # Environment validation
│   ├── post-api-helpers.sh   # Deployment testing
│   └── python/requirements.txt
└── terraform/
    ├── quota-infra.tf        # Main infrastructure
    ├── lambda_function.py    # Quota management logic
    ├── locals.tf             # Configuration settings
    ├── variables.tf          # Input variables
    ├── outputs.tf            # Resource outputs
    └── providers.tf.jinja    # AFT provider config
```

## Monitoring

The system runs automatically every 10 minutes. When quotas are approved, you'll get notifications in #ccoe-notifications.

Post-deployment, the script shows a summary like:
```
=== SECURITY GROUPS ===
Region          Current    Target     Status
us-east-1       200        200        OK
us-west-2       200        200        OK
Summary: 5/5 regions at target (200)

=== OVERALL STATUS ===
Status: 5/10 quotas at target across 5 regions
```