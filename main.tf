# define the provider
provider "aws" {
    region = "ap-southeast-1"
  
}

## create a virtual network
 resource "aws_vpc" "my_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "My_vpc"
    }
   
 }
  #### create your aaplication segment
  resource "aws_subnet" "my_app_subnet" {
    tags = {
      Name =  "APP_subnet"
    }
     vpc_id = aws_vpc.my_vpc.id
     cidr_block = "10.0.1.0/24"
     map_public_ip_on_launch = true
     depends_on = [
       aws_vpc.my_vpc
     ]
  }


#### define routing table
resource "aws_route_table" "my_route-table" {
    tags = {
        Name = "MY_route_table"

    }
  
  vpc_id = aws_vpc.my_vpc.id
}

# associate subnet with routing table
resource "aws_route_table_association" "App_route_association" {
    subnet_id = aws_subnet.my_app_subnet.id
    route_table_id = aws_route_table.my_route-table.id

  
}

## create internet gateway for servers to be connected to internet
 resource "aws_internet_gateway" "My_IG" {
    tags = {
      Name = "MY_IGW"

    }
   vpc_id = aws_vpc.my_vpc.id
   depends_on = [
     aws_vpc.my_vpc
   ]
 }
  
  ## add default route to routing table to point to the internet

resource "aws_route" "default_route" {
    route_table_id = aws_route_table.my_route-table.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.My_IG.id

}

#### create a security group

resource "aws_security_group" "APP_SG" {
  name = "APP_SG"
  description = "Allow Web inbound Traffic"
  vpc_id = aws_vpc.my_vpc.id  
  ingress  {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "NFS"
    from_port = 2049
    to_port = 2049
    cidr_blocks = ["0.0.0.0/0"]

  }
  egress  {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]

  }
}

### create a private key whic can  be used  to login to the web server

resource "tls_private_key" "Web_key" {
    algorithm = "RSA"
  
}

# save public key attributes from the generated keys
resource "aws_key_pair" "App-Instance-key" {
    key_name = "Web-key"
    public_key = tls_private_key.Web_key.public_key_openssh

}

### save the key to your local system
resource "local_file" "Web_key" {
    content = tls_private_key.Web_key.private_key_pem
    filename = "Web-key.pem"
  
}
#### create your web server instance
 resource "aws_instance" "Web" {
        ami = "ami-064eb0bee0c5402c5"
        instance_type = "t2.micro"
        tags = {
            Name = "Webserver1"
        }
   
   count = 1
   subnet_id = aws_subnet.my_app_subnet.id
   key_name = "Web-key"
   security_groups = [aws_security_group.APP_SG.id]


   provisioner "remote-exec" {
    connection {
      type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.Web_key.private_key_pem
        host = aws_instance.Web[0].map_public_ip
    }
     inline = [
       "sudo yum install httpd php git -y",
       "sudo systemctl restart httpd",
       "sudo systemctl enable httpd"
     ]
     
   }
 }

 ###creating EFS file system

resource "aws_efs_file_system" "my_nfs" {
    depends_on = [
      aws_security_group.APP_SG,aws_instance.Web
    ]
  creation_token = "my_nfs"
  tags = {
    Name = "my_nfs"
  }
}

## mounting EFS FILE SYSTEM
resource "aws_efs_mount_target" "mount" {
    depends_on = [
      aws_efs_file_system.my_nfs
    ]
    file_system_id = aws_efs_file_system.my_nfs.id
    subnet_id = aws_instance.Web[0].subnet_id
    security_groups = ["${aws_security_group.APP_SG.id}"]
  
}

resource "null_resource" "EC2-Mount" {
    depends_on = [
      aws_efs_mount_target.mount
    ]
  connection {
      type = "ssh"
      user = "ec2-user"
      private_key = tls_private_key.Web_key.private_key_pem
      host = aws_instance.Web[0].public_ip

  }
  provisioner "remote-exec" {
    inline = [
        "sudo mount -t nfs4 ${aws_efs_mount_target.mount.ip_address}:/  /var/www/html/",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone  https://github.com/vineets300/webpage2.git /var/www/html"]

  }
}

## create a bucket to upload your  static data like images
resource "aws_s3_bucket" "demonewbucket12345" {
    bucket = "demonewbucket12345"
    acl = "public-read-write"
    region = "ap-southeast-1"

    versioning {
        enabled = true

    }
tags = {
    Name = "demonewbucket12345"
    Enviornment = "prod"

}
  
  provisioner "local-exec" {
    command = "git clone https://github.com/vineets300/Webpage2.git web-server-image/Demo2.PNG"
  }
}
 ## allow public access  to the bucket
  resource "aws_s3_bucket_public_access_block" "public_storage" {
    depends_on = [
      aws_s3_bucket.demonewbucket12345
    ]
    bucket = "demonewbucket12345"
    block_public_acls = false
    block_public_policy = false

  }

#### upload your data to s3 bucket
resource "aws_s3_bucket_object" "object1" {
    depends_on = [
      aws_s3_bucket.demonewbucket12345
    ]
  bucket = "demonewbucket12345"
  acl = "public-read-write"
  key = "Demo2.PNG"
  source = "web_server-image/Demo2.PNG"

}
## defune s3 id
locals {
  s3_origin_id = "s3-origin"
}

### create a cloudfront distribution for cdn
resource "aws_cloudfront_distribution" "tera_cloudfront1" {
    depends_on = [
      aws_s3_bucket_object.object1
    ]
  origin {
    domain_name = aws_s3_bucket.demonewbucket12345.bucket
    origin_id = local.s3_origin_id

  }
  enabled = true
  default_cache_behavior {
    allowed_methods = ["DELETE","GET","HEAD","OPTIONS","PATCH"]
    cached_methods = ["GET","HEAD"]
    target_origin_id = local.s3_origin_id

forwarded_values {
  query_string = false

  cookies {
    forward = "none"

  }
}
viewer_protocol_policy = "allow-all"
min_ttl =  0
default_ttl = 3600
max_ttl = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true

  }
}

## update the cdn image url to your web server  code 
resource "null_resource" "write_image" {
depends_on = [aws_cloudfront_distribution.tera-cloudfront1]
connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.Web_key.private_key_pem
    host = aws_instance.Web[0].public_ip

}
provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${aws_cloudfront_distribution.tera-cloudfront1}'\"",
      "echo \"</body>\" >>  /var/www/html/index.html",
      "echo \"</html>\" >>  /var/www/html/index.html",
      "EOF"

    ]
  
}
}
### success image storing the result in a file
resource "null_resource" "result" {
    depends_on = [
      null_resource.EC2-Mount
    ]
    provisioner "local-exec" {
        command = "echo the website has been deployed successfully and >> "
      
    }
  
}


## test application
resource "null_resource" "running_the_website" {
    depends_on = [
      null_resource.write_image
    ]
provisioner "local-exec" {
    command = "start chrome ${aws_instance.web[0].public_ip
    }"

}  
}