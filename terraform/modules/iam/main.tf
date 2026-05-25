# modules/iam/main.tf
# Least-privilege IAM roles for Glue, Redshift, Athena, and SageMaker (bonus).

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "redshift_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "athena_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      # Athena queries are executed in the caller's identity context;
      # this role is used by EC2/Lambda/ECS services that query on behalf of users.
      identifiers = ["lambda.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Glue Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "glue" {
  name               = "${var.name_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

# Attach AWS managed Glue Service Role (includes CloudWatch and Glue API access)
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_s3" {
  # Read from raw
  statement {
    sid     = "ReadRaw"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
    ]
  }
  # Write to staging
  statement {
    sid     = "WriteStaging"
    actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      var.staging_bucket_arn,
      "${var.staging_bucket_arn}/*",
    ]
  }
  # Read scripts from glue-scripts bucket
  statement {
    sid     = "ReadGlueScripts"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.glue_scripts_bucket_arn,
      "${var.glue_scripts_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_s3" {
  name   = "${var.name_prefix}-glue-s3-policy"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_s3.json
}

# ---------------------------------------------------------------------------
# Redshift Serverless Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "redshift" {
  name               = "${var.name_prefix}-redshift-role"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume.json
}

data "aws_iam_policy_document" "redshift_s3" {
  statement {
    sid     = "ReadCurated"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }
  # Redshift Spectrum can also read staging data
  statement {
    sid     = "ReadStaging"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.staging_bucket_arn,
      "${var.staging_bucket_arn}/*",
    ]
  }
  statement {
    sid     = "GlueDataCatalogRead"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = ["*"]   # Glue Data Catalog does not support resource-level ARNs for GetTable
  }
}

resource "aws_iam_role_policy" "redshift_s3" {
  name   = "${var.name_prefix}-redshift-s3-policy"
  role   = aws_iam_role.redshift.id
  policy = data.aws_iam_policy_document.redshift_s3.json
}

# ---------------------------------------------------------------------------
# Athena Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "athena" {
  name               = "${var.name_prefix}-athena-role"
  assume_role_policy = data.aws_iam_policy_document.athena_assume.json
}

data "aws_iam_policy_document" "athena_policy" {
  statement {
    sid     = "AthenaWorkgroupAccess"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "ReadRawStaging"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
      var.staging_bucket_arn,
      "${var.staging_bucket_arn}/*",
    ]
  }
  statement {
    sid     = "WriteAthenaResults"
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = [
      var.athena_results_bucket_arn,
      "${var.athena_results_bucket_arn}/*",
    ]
  }
  statement {
    sid     = "GlueCatalogRead"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "athena" {
  name   = "${var.name_prefix}-athena-policy"
  role   = aws_iam_role.athena.id
  policy = data.aws_iam_policy_document.athena_policy.json
}

# ---------------------------------------------------------------------------
# SageMaker Role (Bonus — Part 5)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "sagemaker" {
  name               = "${var.name_prefix}-sagemaker-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker.name
  # Scoped-down in production; AmazonSageMakerFullAccess is used here for dev convenience.
  # In prod, replace with a custom policy granting only required SageMaker actions.
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

data "aws_iam_policy_document" "sagemaker_s3" {
  statement {
    sid = "ReadFeatureStore"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.curated_bucket_arn,
      "${var.curated_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "sagemaker_s3" {
  name   = "${var.name_prefix}-sagemaker-s3-policy"
  role   = aws_iam_role.sagemaker.id
  policy = data.aws_iam_policy_document.sagemaker_s3.json
}
