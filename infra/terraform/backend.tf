terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "mega/eks/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
