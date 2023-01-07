# -----------------------------------------------
# S3 BUCKET - For access logs
# -----------------------------------------------

resource "random_string" "random" {
  length  = 7
  lower   = true
  numeric = false
  upper   = false
  special = false
  keepers = {
    name_prefix = var.name_prefix
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = lower("${random_string.random.keepers.name_prefix}-logs-${random_string.random.result}")
  tags = merge(
    var.tags,
    {
      Name = lower("${random_string.random.keepers.name_prefix}-logs-${random_string.random.result}")
    },
  )
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = var.enable_s3_bucket_server_side_encryption ? 1 : 0

  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_bucket_server_side_encryption_sse_algorithm
      kms_master_key_id = var.s3_bucket_server_side_encryption_sse_algorithm == "aws:kms" ? var.s3_bucket_server_side_encryption_key : null
    }
  }
}

# -----------------------------------------------
# IAM POLICY DOCUMENT - For access logs to the S3 bucket
# -----------------------------------------------

resource "aws_iam_role" "logging_storage" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags

}

data "aws_iam_policy_document" "logs_access_policy_document" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.logging_storage.arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*", ]
  }
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elb.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid = "https-only"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    effect = "Deny"

    actions = [
      "s3:*",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.logs.id}",
      "arn:aws:s3:::${aws_s3_bucket.logs.id}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = [false]
    }
  }
}

# -----------------------------------------------
# IAM POLICY - For access logs to the s3 bucket
# -----------------------------------------------

resource "aws_s3_bucket_policy" "logs_access_policy" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_access_policy_document.json
}

# -----------------------------------------------
# S3 bucket block public access
# -----------------------------------------------

resource "aws_s3_bucket_public_access_block" "logs_block_public_access" {
  count = var.block_s3_bucket_public_access ? 1 : 0

  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket_policy.logs_access_policy]
}
