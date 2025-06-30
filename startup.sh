#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_status "Starting application setup..."

# Step 1: Get instance IP using IMDSv2
print_status "Fetching instance IP using IMDSv2..."
INSTANCE_IP=""

# Get IMDSv2 token
print_status "Getting IMDSv2 token..."
if command_exists curl; then
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s 2>/dev/null || echo "")
    if [ -n "$TOKEN" ]; then
        INSTANCE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi
fi

if [ -z "$INSTANCE_IP" ]; then
    print_warning "Could not fetch instance IP from IMDSv2. Using localhost as fallback."
    INSTANCE_IP="localhost"
else
    print_status "Instance IP: $INSTANCE_IP"
fi

# Step 2: Generate SSL certificates
print_status "Generating SSL certificates..."

# Create certs directory
mkdir -p certs

# Generate private key
print_status "Generating private key..."
openssl genrsa -out certs/server.key 2048

# Generate certificate (using fetched EC2 IP)
print_status "Generating certificate for IP: $INSTANCE_IP"
openssl req -new -x509 -key certs/server.key -out certs/server.crt -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$INSTANCE_IP"

# Set proper permissions
print_status "Setting proper file permissions..."
chmod 600 certs/server.key
chmod 644 certs/server.crt

print_status "SSL certificates generated successfully in ./certs/"

# Step 3: Download docker-compose file
print_status "Downloading docker-compose file..."

# TODO: Replace with actual URL
DOCKER_COMPOSE_URL="https://your-url-here/docker-compose.yml"

if [ -f "docker-compose.yml" ]; then
    print_warning "docker-compose.yml already exists. Creating backup..."
    mv docker-compose.yml docker-compose.yml.backup
fi

if command_exists wget; then
    wget "$DOCKER_COMPOSE_URL" -O docker-compose.yml
elif command_exists curl; then
    curl -L "$DOCKER_COMPOSE_URL" -o docker-compose.yml
else
    print_error "Neither wget nor curl is available. Please install one of them."
    exit 1
fi

if [ ! -f "docker-compose.yml" ]; then
    print_error "Failed to download docker-compose.yml"
    exit 1
fi

print_status "Docker compose file downloaded successfully"

# Step 4: Check if Docker and Docker Compose are installed
print_status "Checking Docker installation..."

if ! command_exists docker; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Step 5: Set environment variables for the application
export INSTANCE_IP="$INSTANCE_IP"
export SSL_CERT_PATH="./certs/server.crt"
export SSL_KEY_PATH="./certs/server.key"

print_status "Environment variables set:"
print_status "  INSTANCE_IP=$INSTANCE_IP"
print_status "  SSL_CERT_PATH=$SSL_CERT_PATH"
print_status "  SSL_KEY_PATH=$SSL_KEY_PATH"

# Step 6: Run Docker Compose
print_status "Starting application with Docker Compose..."

# Check if we should use 'docker compose' or 'docker-compose'
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# Stop any existing containers
print_status "Stopping any existing containers..."
sudo $DOCKER_COMPOSE_CMD down 2>/dev/null || true

# Pull latest images and start services
print_status "Pulling latest images and starting services..."
sudo $DOCKER_COMPOSE_CMD pull
sudo $DOCKER_COMPOSE_CMD up -d

# Wait a moment for services to start
sleep 5

# Check if containers are running
print_status "Checking container status..."
sudo $DOCKER_COMPOSE_CMD ps

print_status "Application setup completed successfully!"
print_status "SSL certificates are available in ./certs/"
print_status "Instance IP: $INSTANCE_IP"
print_status "Application should be accessible at: http://$INSTANCE_IP"

# Optional: Show logs
read -p "Do you want to view the application logs? (y/n): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo $DOCKER_COMPOSE_CMD logs -f
fi