# aws/00-remote-backend

## Purpose
The S3 bucket that holds the state of `01-networking` and `02-eks`.

## Provisions
- `aws_s3_bucket.this`: `istio-p6-<account ID>-useast1-tfstate`, versioned, AES256, public access blocked
- `aws_s3_bucket_versioning.this`, `aws_s3_bucket_server_side_encryption_configuration.this`, `aws_s3_bucket_public_access_block.this`

## Consumes
- nothing (`data.aws_caller_identity.current` for the account ID in the bucket name)

## Provides
- `state_bucket`

## Notes
- No backend block: this stack's own state stays local and is destroyed last by `scripts/teardown.sh`.
- `force_destroy = true` is a lab value: the teardown removes the bucket with its object versions.
