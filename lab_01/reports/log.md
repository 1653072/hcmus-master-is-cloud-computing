```sh
make up
```

  ✓ AWS identity: 122298909886  arn:aws:sts::122298909886:assumed-role/AccountFullAccessRole/e498d478-10e1-70ff-dec7-b5bffb709f18
  ✓ Region: ap-southeast-2   Project: lab01-wp
  ✓ Access: EC2 (VPC, instances, SGs)
  ✓ Access: ELB (load balancers)
  ✓ Access: RDS (MySQL)
  ✓ Access: EFS (file systems)
  ✓ Access: SSM (AMI lookup)
==> Discovering network in ap-southeast-2
  ✓ VPC      vpc-0556a926ed973904f
  ✓ Subnet 1 subnet-05d506a06d830aede (ap-southeast-2a)
  ✓ Subnet 2 subnet-015884ad9451019f5 (ap-southeast-2b)
==> Creating security groups in vpc-0556a926ed973904f
  ✓ lab01-wp-alb-sg = sg-0e9068f5f70a65231
  ✓ lab01-wp-web-sg = sg-09c2993c9983b9966
  ✓ lab01-wp-efs-sg = sg-0f28be3629fa0ac30
  ✓ lab01-wp-db-sg = sg-0ecedb0481624c134
==> Adding rules
  ✓ ALB  tcp/80   from 0.0.0.0/0    : sgr-05f3d53d223d9ba07
  ✓ WEB  tcp/80   from lab01-wp-alb-sg : sgr-0eb9f1b9a02111a73
  ✓ EFS  tcp/2049 from lab01-wp-web-sg : sgr-0985c47f9aa6833b3
  ✓ RDS  tcp/3306 from lab01-wp-web-sg : sgr-0eddfb8b8eef1e98d
  ✓ WEB  tcp/22   from 123.20.149.146/32 : sgr-040bd3a0868af39f8
  ✓ WEB  tcp/22   from 123.20.219.144/32 : sgr-0f9a9e6bc4a12cbe7
  ✓ EFS = fs-03241c2c3984501fb
==> Waiting for EFS fs-03241c2c3984501fb to be available (timeout 300s)...
  ✓ EFS fs-03241c2c3984501fb to be available
  ✓ Mount target 1 = fsmt-00e6c4cb32db7942b (subnet-05d506a06d830aede)
  ✓ Mount target 2 = fsmt-0ca7ecd7ae9112200 (subnet-015884ad9451019f5)
==> Waiting for EFS mount targets to be available (timeout 600s)...
  ✓ EFS mount targets to be available
  ✓ DB subnet group = lab01-wp-db-subnets
==> Creating RDS MySQL instance lab01-wp-db (db.t3.micro)
  ✓ RDS lab01-wp-db status = creating
==> Waiting for lab01-wp-db to be available (usually 5-10 min)...
  ✓ RDS endpoint = lab01-wp-db.cd40yim44hyw.ap-southeast-2.rds.amazonaws.com
  ✓ Key pair lab01-wp-key -> /Users/alpha/Alpha/tmp/hcmus-master-is-cloud-computing/lab_01/.state/lab01-wp-key.pem
  ✓ AMI = ami-013f66a12d3857f32 (x86_64)
  ✓ lab01-wp-web-1 = i-0cb1a682bd95d2f50 (ap-southeast-2a)
  ✓ lab01-wp-web-2 = i-02754c9cecc238ff0 (ap-southeast-2b)
==> Waiting for instances to be running...
  ✓ web-1 running, public IP 3.27.71.27
  ✓ web-2 running, public IP 16.179.199.82
==> WordPress bootstrap runs in the background on each VM (~3-5 min). Logs: make logs N=1
  ✓ Target group = lab01-wp-tg
  ✓ Registered targets: i-0cb1a682bd95d2f50 i-02754c9cecc238ff0
  ✓ Load balancer = lab01-wp-alb
==> Waiting for the load balancer to be active...
  ✓ Listener HTTP:80 -> lab01-wp-tg
  ✓ Load balancer URL: http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com/
==> Waiting for both web servers to be healthy behind the ALB (timeout 900s)...
  ✓ both web servers to be healthy behind the ALB
==> Waiting for http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com to answer (timeout 300s)...
  ✓ http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com to answer
==> Installing WordPress ('HCMUS Cloud Computing Lab 01', admin user 'admin')
  ✓ WordPress installed
  ✓ Home page title: HCMUS Cloud Computing Lab 01

  WordPress is ready
  ------------------
  Site:     http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com/
  Admin:    http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com/wp-admin/
  User:     admin
  Password: 9d55f086a23893b88035   (stored in .state/secrets.env)

==> GET http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com/ x 8
  #1  HTTP 200  served by i-02754c9cecc238ff0 (ap-southeast-2b)
  #2  HTTP 200  served by i-0cb1a682bd95d2f50 (ap-southeast-2a)
  #3  HTTP 200  served by i-0cb1a682bd95d2f50 (ap-southeast-2a)
  #4  HTTP 200  served by i-02754c9cecc238ff0 (ap-southeast-2b)
  #5  HTTP 200  served by i-0cb1a682bd95d2f50 (ap-southeast-2a)
  #6  HTTP 200  served by i-02754c9cecc238ff0 (ap-southeast-2b)
  #7  HTTP 200  served by i-02754c9cecc238ff0 (ap-southeast-2b)
  #8  HTTP 200  served by i-0cb1a682bd95d2f50 (ap-southeast-2a)
  ✓ Title: HCMUS Cloud Computing Lab 01
  ✓ Open:  http://lab01-wp-alb-857961228.ap-southeast-2.elb.amazonaws.com/

```sh
scripts/ssh.sh 1 'hostname; ls -l /var/www/html/wp-content/uploads/2026/11/'
```

  Warning: Permanently added '3.27.71.27' (ED25519) to the list of known hosts.
  ip-172-31-0-175.ap-southeast-2.compute.internal
  total 44
  -rw-r--r--. 1 apache apache  5112 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n-150x150.jpg
  -rw-r--r--. 1 apache apache 11228 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n-300x298.jpg
  -rw-r--r--. 1 apache apache 21438 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n.jpg

```sh
scripts/ssh.sh 2 'hostname; ls -l /var/www/html/wp-content/uploads/2026/11/'
```

  Warning: Permanently added '16.179.199.82' (ED25519) to the list of known hosts.
  ip-172-31-39-59.ap-southeast-2.compute.internal
  total 44
  -rw-r--r--. 1 apache apache  5112 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n-150x150.jpg
  -rw-r--r--. 1 apache apache 11228 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n-300x298.jpg
  -rw-r--r--. 1 apache apache 21438 Nov 18 14:56 699752077_3208999729271844_1127526474387623832_n.jpg
