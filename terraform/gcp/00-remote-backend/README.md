# gcp/00-remote-backend

## Purpose
The GCS bucket that holds the state of `01-networking` and `02-gke`, and the project APIs they call.

## Provisions
- `google_storage_bucket.this`: `<project ID>-tfstate`, versioned, uniform access, public access prevention enforced
- `google_project_service.this[*]`: compute, container, iam

## Consumes
- nothing

## Provides
- `state_bucket`, `enabled_services`

## Notes
- No backend block: this stack's own state stays local and is destroyed last by `scripts/teardown.sh`.
- `force_destroy = true` is a lab value.
