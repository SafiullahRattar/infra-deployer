terraform {
  backend "s3" {
    bucket         = "infra-deployer-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-deployer-tflock"
    encrypt        = true
  }
}
