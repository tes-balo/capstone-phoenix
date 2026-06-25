launch template vs user data

They solve different problems and are often used together, not as alternatives.

Feature User Data Launch Template
What it is A startup script run when an EC2 instance boots A reusable blueprint for launching EC2 instances
Purpose Configure the instance after launch Define how instances should be launched
Contains Bash scripts, cloud-init config AMI, instance type, security groups, key pair, user data, IAM role, EBS volumes, etc.
Scope Instance initialization Entire instance configuration
Reusability Script only Full launch configuration
Used by EC2, Auto Scaling, EKS node groups, Launch Templates EC2, Auto Scaling Groups, EKS Managed Node Groups, Spot Fleets
User Data

Think of User Data as:

"What should this server do when it starts?"

Example:

# !/bin/bash

yum update -y
yum install docker -y
systemctl enable docker
systemctl start docker

When the EC2 instance boots:

OS starts
User Data runs
Docker gets installed
Launch Template

Think of a Launch Template as:

"How should AWS create this server?"

Example:

AMI: Amazon Linux 2023
Instance Type: t3.medium
Security Group: web-sg
IAM Role: ec2-role
Key Pair: phoenix-key
Storage: 20GB gp3
User Data: install docker script

Now whenever AWS needs a server, it uses this blueprint.

How They Work Together

A Launch Template can contain User Data.

Launch Template
├── AMI
├── Instance Type
├── Security Group
├── IAM Role
├── Storage
└── User Data Script

AWS launches the EC2 instance using the template.

Then the instance boots and executes the User Data script.

In Your DevOps Capstone

For a production-style setup:

Bad
Create EC2 manually
SSH into server
Install Docker manually
Install K3s manually

Not reproducible.

Better
Launch Template
└── User Data
    ├── Install Docker
    ├── Install K3s
    └── Join Cluster

Now every new node is configured automatically.

Common Interview Question

Can you launch an EC2 instance without User Data?

✅ Yes

Can you launch an EC2 instance without a Launch Template?

✅ Yes (manually through the console or CLI)

Can a Launch Template contain User Data?

✅ Yes — this is the most common pattern in Auto Scaling Groups and EKS.

For your Phoenix capstone architecture, I'd recommend:

Auto Scaling Group
        │
        ▼
Launch Template
        │
        ▼
User Data
        │
        ├── Install Docker
        ├── Install K3s Agent
        └── Register with cluster

That's the pattern most closely aligned with how real-world Kubernetes worker nodes are provisioned on AWS.

show me a configuration with launch template

Here's a realistic Terraform configuration that creates:

A Security Group
A Launch Template
An Auto Scaling Group
User Data embedded inside the Launch Template

This is very close to what you'd see in a production DevOps environment.

User Data Script

Create userdata.sh:

# !/bin/bash

yum update -y
yum install -y docker

systemctl start docker
systemctl enable docker

usermod -aG docker ec2-user

echo "Node provisioned successfully" > /tmp/provision.log
Security Group
resource "aws_security_group" "web_sg" {
  name = "phoenix-web-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
Launch Template
resource "aws_launch_template" "web_lt" {
  name_prefix   = "phoenix-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  user_data = base64encode(
    file("${path.module}/userdata.sh")
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "Phoenix-Node"
      Project = "Phoenix-Capstone"
    }
  }
}
Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  name = "phoenix-asg"

  min_size         = 2
  max_size         = 5
  desired_capacity = 2

  vpc_zone_identifier = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }
}
Architecture Flow
Auto Scaling Group
        │
        ▼
Launch Template
        │
        ├── AMI
        ├── Instance Type
        ├── Security Group
        ├── IAM Role
        └── User Data
                 │
                 ▼
        Install Docker
        Configure Node
        Join Cluster

For your Phoenix capstone, you could make the User Data script install a K3s agent automatically:

curl -sfL <https://get.k3s.io> | \
K3S_URL=https://<SERVER-IP>:6443 \
K3S_TOKEN=<TOKEN> \
sh -

Then every EC2 instance launched by the Auto Scaling Group automatically becomes a Kubernetes worker node. This is a common pattern when demonstrating infrastructure automation and self-healing clusters.
