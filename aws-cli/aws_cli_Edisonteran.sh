#!/bin/bash
# Martes 4 de Febreo 2025 08:35
#SCRIPT de Edison Javier Cachiguango Teran(ecachiguangot@educantabria.es)
echo "En breve se iniciará el despliegue de infraestructura en AWS..."

# VARIABLES 
# =======================

KEY_NAME="ssh-mensagl-2025-edisoncachiguango"
VPC_NAME="VPC-mensagl-2025-edisoncachiguango"
DB_SUBNET_GROUP_NAME="subnet-group-edisoncachiguango"
RDS_INSTANCE_ID="mysql-db-mensagl-2025"
REGION="us-east-1"
AMI_ID="ami-04b4f1a9cf54c11d0"  # Sera un Ubuntu Server 24.04 en us-east-1

# Creacion de claves SSH
# =======================

echo "Se está creando clave SSH..."
aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem
chmod 400 $KEY_NAME.pem

# Creación de VPC y Subredes en 2 AZs
# =======================

echo "Comenzando la creacion VPC y Subredes..."

VPC_ID=$(aws ec2 create-vpc --cidr-block 10.204.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Asignara un nombre a la VPC
# =======================

aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="VPC-Mensagl-2025-edisonteran"

# Las subredes en 2 AZs
# =======================

SUBNET_PUBLIC1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.204.1.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_PUBLIC2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.204.2.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)

SUBNET_PRIVATE1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.204.3.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.204.4.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)

# Asignar nombres a las subredes
# =======================

aws ec2 create-tags --resources $SUBNET_PUBLIC1_ID --tags Key=Name,Value="Subnet-Publica-1"
aws ec2 create-tags --resources $SUBNET_PUBLIC2_ID --tags Key=Name,Value="Subnet-Publica-2"
aws ec2 create-tags --resources $SUBNET_PRIVATE1_ID --tags Key=Name,Value="Subnet-Privada-1"
aws ec2 create-tags --resources $SUBNET_PRIVATE2_ID --tags Key=Name,Value="Subnet-Privada-2"

echo "Subredes creadas: "

echo "   - Pública 1: $SUBNET_PUBLIC1_ID"
echo "   - Pública 2: $SUBNET_PUBLIC2_ID"
echo "   - Privada 1: $SUBNET_PRIVATE1_ID"
echo "   - Privada 2: $SUBNET_PRIVATE2_ID"

# Asignar Gateway de Internet
# =======================

echo "Creando Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

echo "Internet Gateway creado y adjuntado correctamente..."

# Configuracion de subred pública para asignación automática de IP pública
echo "Asignación automática de IPs públicas en la subred pública..."
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC1_ID --map-public-ip-on-launch

# Creación de tabla de rutas para la subred pública
echo "Creancion de tabla de rutas para la subred pública..."
RTB_PUBLIC_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)

# Asociar la tabla de rutas con la subred pública
echo "Asociando subred pública a la tabla de rutas pública..."
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC_ID --subnet-id $SUBNET_PUBLIC1_ID

# Agregar una ruta para acceso a Internet
echo "Configurando acceso a Internet para la subred pública..."
aws ec2 create-route --route-table-id $RTB_PUBLIC_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

echo "Configuración de Internet Gateway y tabla de rutas pública hecha. Ahora es pública."

# Creación de NAT Gateway y tabla de rutas privada
# =======================

echo "Creando Elastic IP para NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address --query 'AllocationId' --output text)

# Creación del NAT Gateway
echo "Creación NAT Gateway en la Subred Pública 1"
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC1_ID --allocation-id $EIP_ALLOC_ID --query 'NatGateway.NatGatewayId' --output text)

echo "Esperando a que el NAT Gateway esté disponible..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID

echo "NAT Gateway creado correctamente y disponible"

# Creación de tabla de rutas para la subred privada
echo "Creando tabla de rutas para la subred privada..."
RTB_PRIVATE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)

# Asociar la tabla de rutas con la subred privada
echo "Asociando la subred privada a la tabla de rutas privada..."
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE_ID --subnet-id $SUBNET_PRIVATE1_ID
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE_ID --subnet-id $SUBNET_PRIVATE2_ID

# Agregar una ruta para acceso a Internet en la subred privada
echo "Configurando NAT Gateway como salida a Internet para las subredes privadas..."
aws ec2 create-route --route-table-id $RTB_PRIVATE_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID

echo "Configuración de NAT Gateway y tabla de rutas privada completada. Ahora las subredes privadas tienen acceso a Internet."


# Crear Grupos de Seguridad
# =======================

echo "Creando Grupos de Seguridad"

SG_PROXY_ID=$(aws ec2 create-security-group --group-name SG-Proxy --description "Proxy Inverso" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_XMPP_ID=$(aws ec2 create-security-group --group-name SG-XMPP --description "Servidor Mensajeria" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_DB_XMPP_ID=$(aws ec2 create-security-group --group-name SG-DB-XMPP --description "Base de Datos para Mensajeria" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_CMS_ID=$(aws ec2 create-security-group --group-name SG-CMS --description "CMS Soporte" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_DB_CMS_ID=$(aws ec2 create-security-group --group-name SG-DB-CMS --description "Base de Datos CMS" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Reglas para SG-Proxy (Acceso público HTTP, HTTPS, SSH)
# =======================

aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# Reglas para SG-XMPP (El servidor de Mensajería)
# =======================

aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 5222 --source-group $SG_PROXY_ID
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 5269 --source-group $SG_PROXY_ID
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 5280 --source-group $SG_PROXY_ID
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 22 --source-group $SG_PROXY_ID

# Reglas para SG-DB-XMPP (La base de datos de Mensajería)
# =======================

aws ec2 authorize-security-group-ingress --group-id $SG_DB_XMPP_ID --protocol tcp --port 3306 --source-group $SG_XMPP_ID
aws ec2 authorize-security-group-ingress --group-id $SG_DB_XMPP_ID --protocol tcp --port 22 --source-group $SG_PROXY_ID

# Reglas para SG-CMS (El servidor CMS Soporte)
# =======================

aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 22 --source-group $SG_PROXY_ID

# Reglas para SG-DB-CMS (La base de datos de CMS Soporte)
# =======================

aws ec2 authorize-security-group-ingress --group-id $SG_DB_CMS_ID --protocol tcp --port 3306 --source-group $SG_CMS_ID
aws ec2 authorize-security-group-ingress --group-id $SG_DB_CMS_ID --protocol tcp --port 22 --source-group $SG_PROXY_ID

# Crear Instancias EC2 con los grupos de seguridad asignados correctamente
# =======================

echo "Creando las instancias en EC2"

# Proxy Nginx 1 y 2 con IP publica
# =======================

INSTANCE_PROXY1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PUBLIC1_ID --private-ip-address 10.204.1.10 --security-group-ids $SG_PROXY_ID --associate-public-ip-address --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_PROXY1_ID --tags Key=Name,Value="Proxyinverso1"

INSTANCE_PROXY2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PUBLIC2_ID --private-ip-address 10.204.2.10 --security-group-ids $SG_PROXY_ID --associate-public-ip-address --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_PROXY2_ID --tags Key=Name,Value="Proxyinverso2"

# XMPP Servers (Mensajería 1 y 2)
# =======================

INSTANCE_XMPP1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE1_ID --private-ip-address 10.204.3.10 --security-group-ids $SG_XMPP_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_XMPP1_ID --tags Key=Name,Value="Mensajeria1"

INSTANCE_XMPP2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE1_ID --private-ip-address 10.204.3.20 --security-group-ids $SG_XMPP_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_XMPP2_ID --tags Key=Name,Value="Mensajeria2"

# Crear la instancia PostgreSQL con instalación automática de Ejabberd DB
# =======================

echo "Creancion de instancia EC2 para PostgreSQL con USER DATA."

INSTANCE_PGSQL_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_PRIVATE1_ID \
    --private-ip-address 10.204.3.30 \
    --security-group-ids $SG_DB_XMPP_ID \
    --user-data file://setup_postgresql_ejabberd.sh \
    --query 'Instances[0].InstanceId' \
    --output text)

aws ec2 create-tags --resources $INSTANCE_PGSQL_ID --tags Key=Name,Value="Postgresql"

echo "La instancia PostgreSQL desplegada y configurada correctamente."


# Servidores de Soporte 1 y 2
# =======================

INSTANCE_SOPORTE1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE2_ID --private-ip-address 10.204.4.10 --security-group-ids $SG_CMS_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_SOPORTE1_ID --tags Key=Name,Value="Soporte1"

INSTANCE_SOPORTE2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE2_ID --private-ip-address 10.204.4.20 --security-group-ids $SG_CMS_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_SOPORTE2_ID --tags Key=Name,Value="Soporte2"

# Crear Grupo de Subredes RDS
# =======================

echo "Creando grupo de subredes para RDS MySQL"

aws rds create-db-subnet-group --db-subnet-group-name "cms-db-subnet-group" --db-subnet-group-description "Grupo de subredes para RDS MySQL CMS" --subnet-ids $SUBNET_PRIVATE1_ID $SUBNET_PRIVATE2_ID --tags Key=Name,Value="cms-db-subnet-group"
echo "Grupo de subredes creado"

# Crear Instancia RDS MySQL
# =======================

echo "Creando instancia de RDS MySQL"

aws rds create-db-instance \
    --db-instance-identifier "cms-database" \
    --allocated-storage 20 \
    --storage-type "gp2" \
    --db-instance-class "db.t3.micro" \
    --engine "mysql" \
    --engine-version "8.0" \
    --master-username "admin" \
    --master-user-password "Admin123" \
    --db-name "wordpress_db" \
    --db-subnet-group-name "cms-db-subnet-group" \
    --vpc-security-group-ids "$SG_DB_CMS_ID" \
    --publicly-accessible \
    --tags Key=Name,Value="wordpress_db"

echo "La instancia RDS MySQL fue creada correctamente"

echo "HASTA LA PROXIMA.........."
