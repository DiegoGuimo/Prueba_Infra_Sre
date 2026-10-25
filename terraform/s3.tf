# ===========================================================================
# S3 — implementa docs/01-diseno.md §3.4
#   - Bucket privado con nombre único (sufijo aleatorio)
#   - Block Public Access en las 4 configuraciones
#   - Versionado habilitado
#   - Cifrado SSE-S3 por defecto
#   - Bucket policy que restringe el acceso al rol IAM de la Lambda
# ===========================================================================

# Sufijo aleatorio para garantizar unicidad global del nombre del bucket.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "results" {
  bucket = "${var.project_name}-results-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-results"
  }
}

# Block Public Access — las 4 configuraciones habilitadas.
resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy      = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionado habilitado.
resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cifrado en reposo con SSE-S3 (AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket policy: solo el rol de la Lambda puede operar sobre el bucket.
# Además se fuerza TLS (deny a cualquier acceso sin HTTPS).
data "aws_iam_policy_document" "bucket_policy" {
  # Permitir al rol de la Lambda las operaciones necesarias.
  statement {
    sid    = "AllowLambdaRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*",
    ]
  }

  # Denegar cualquier acceso que no use TLS.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "results" {
  bucket = aws_s3_bucket.results.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  # El bucket policy depende del rol de la Lambda (principal).
  depends_on = [aws_iam_role.lambda]
}
