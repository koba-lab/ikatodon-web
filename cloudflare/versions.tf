terraform {
  required_version = "~> 1.16"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # state は Cloudflare R2（S3 互換）に置く。state にはトンネルの secret などが平文で入るため、
  # リポジトリには絶対にコミットしない。
  # エンドポイントは環境変数 AWS_ENDPOINT_URL_S3、認証情報は AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY で渡す（docs/setup.md 参照）。
  backend "s3" {
    bucket = "ikatodon-web-tfstate"
    key    = "cloudflare/terraform.tfstate"
    region = "auto"

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

# API トークンは環境変数 CLOUDFLARE_API_TOKEN で渡す。
provider "cloudflare" {}
