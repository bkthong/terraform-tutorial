/*
    db_password to be supplied in terraform.tfvars (for me)
    in exercise they use the cloud to set the variable for the workspace
*/

/*
    Student can refer to part04.md and modify hard coded
    cidr to variable reference
*/
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}


/*
    Snippet given for subnet, assumption aws_vpc is named "main"
*/
resource "aws_subnet" "main" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-subnet-${count.index}"
  }
}

/*
    Students can refer to part05.md, changing vpc id reference
*/
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

/*
    Students can refer to part05.md
*/
resource "aws_route_table" "main-route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
}

/*
    Student can refer to part05.md but will have to think
    on how to use count and count.index 

    student needs to to know how to use aws_subnet.NAME[INDEX]
    to refer to resourcces with count usage

    All subnetss are associated to the main-route-table

    This part will be tricky for students

*/
resource "aws_route_table_association" "a" {
  count =   length(var.availability_zones)
  subnet_id      = aws_subnet.main[count.index].id  
  route_table_id = aws_route_table.main-route-table.id
}


/*
    Security groups to allow web traffic
    
    Students can refer to part05.md
*/

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.main.id

  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}


/*
    Security groups for ec2 to access rds
*/

resource "aws_security_group" "allow_rds_from_ec2" {
  name        = "allow_rds_from_ec2"
  description = "Allow rds traffic from ec2 security groups"
  vpc_id      = aws_vpc.main.id

  
  ingress {
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    //cidr_blocks = ["0.0.0.0/0"]
    //Allow traffic from security group allow_web
    security_groups = [aws_security_group.allow_web.id]
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_rds"
  }
}


/*
    Studentss can refer to part05.md
    I chose not to create eip and nic
    User data script from ther lower part of student_guide_tf_cloud.md document

    USER_DATA creates contacts database on RDS!!
    - it has terraform resource referencs. Match the references
      to our declarations of rds later!!
    
    UPDATED:
        -  instance_type to use variable
        - availabilty zone , first element in the az list

*/
resource "aws_instance" "web-server-instance" {
  ami               = "ami-085925f297f89fce1"
  instance_type     = var.instance_type
  availability_zone = var.availability_zones[0]
  key_name          = "main-key"  //created in previous exercise
  
  //security_groups = [aws_security_group.allow_web.id]  - this property won't work well based on testing
  vpc_security_group_ids = [aws_security_group.allow_web.id]
  subnet_id = aws_subnet.main[0].id   //otherwise default vpc ubnets are used

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apache2 php php-mysql
              sudo systemctl start apache2
              sudo systemctl enable apache2

              # Create a simple PHP script
              echo "<?php
              \$conn = new mysqli('${aws_db_instance.main.address}', '${var.db_username}', '${var.db_password}', 'contacts');
              if (\$conn->connect_error) {
                  die('Connection failed: ' . \$conn->connect_error);
              }

              if (\$_SERVER['REQUEST_METHOD'] == 'POST') {
                  \$name = \$_POST['name'];
                  \$email = \$_POST['email'];
                  \$sql = \"INSERT INTO contacts (name, email) VALUES ('\$name', '\$email')\";
                  if (\$conn->query(\$sql) === TRUE) {
                      echo 'New record created successfully<br>';
                  } else {
                      echo 'Error: ' . \$sql . '<br>' . \$conn->error;
                  }
              }

              echo '<form method=\"POST\">
                      Name: <input type=\"text\" name=\"name\"><br>
                      Email: <input type=\"email\" name=\"email\"><br>
                      <input type=\"submit\" value=\"Submit\">
                    </form>';

              echo '<br><a href=\"?action=view\">View Contacts</a>';

              if (isset(\$_GET['action']) && \$_GET['action'] == 'view') {
                  \$result = \$conn->query(\"SELECT * FROM contacts\");
                  if (\$result->num_rows > 0) {
                      echo '<table border=\"1\"><tr><th>ID</th><th>Name</th><th>Email</th></tr>';
                      while(\$row = \$result->fetch_assoc()) {
                          echo '<tr><td>'.\$row['id'].'</td><td>'.\$row['name'].'</td><td>'.\$row['email'].'</td></tr>';
                      }
                      echo '</table>';
                  } else {
                      echo 'No contacts found.';
                  }
              }

              \$conn->close();
              ?>" | sudo tee /var/www/html/index.php

              # Create the contacts database and table
              sudo apt-get install -y mysql-client
              mysql -h ${aws_db_instance.main.address} -u ${var.db_username} -p${var.db_password} -e "CREATE DATABASE IF NOT EXISTS contacts; USE contacts; CREATE TABLE IF NOT EXISTS contacts (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), email VARCHAR(255));"

              EOF

  tags = {
    Name = "web-server"
  }
}


/*
    Refer to documetnation for this. 

    https://registry.terraform.io/providers/hashicorp/aws/5.99.1/docs/resources/db_subnet_group

    The subnet group fro rds determines which subnet the rds is created in

    Also getting the subnet ids dynamically via splat expressions
    would be tricky for students. Of course alternatively hard code element
    [0] and element[1], but it would not be scalleable or work well

*/
resource "aws_db_subnet_group" "main_db_subnet" {
  name       = "main-db-subnet"
  subnet_ids = aws_subnet.main[*].id  //splat expression 

  tags = {
    Name = "My DB subnet group"
  }
}

/*
    Student needs to refer to documentation on terraform regisstry
    to complete this.

    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance

    Declaring resource name as "main" to match te user_data script above

    Changes made from documentation snippet:
        - resource name: main
        - multi_az = false added
        - username and password using variables
*/

resource "aws_db_instance" "main" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  
  //ADDED the following, while above was default from example
  multi_az = false  //ADDED - not in the documentation exxample snippet
                    //free tier is only for single az
  db_subnet_group_name = aws_db_subnet_group.main_db_subnet.name   
  vpc_security_group_ids = [aws_security_group.allow_rds_from_ec2.id]
}
