terraform {
  backend "gcs" {
    bucket      = "tf-bookshelf-oleshchenko"
    prefix      = "terraform/state"
    credentials = "C:/Users/Michael/Downloads/gcp-2022-bookshelf-oleshchenko-c2123f2c3308.json"
  }

}
