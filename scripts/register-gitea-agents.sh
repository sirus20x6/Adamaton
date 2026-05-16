#!/bin/bash
# /thearray/gogents/scripts/register-gitea-agents.sh - Register 12 AI agents as Gitea users

# Restrict file modes for any temp/output files we create. Credentials and
# tokens land in user-only output below; this is defense-in-depth in case any
# helper still writes to a default-permissions location.
umask 077

set -euo pipefail

echo "🤖 GoGents Agent Registration for Gitea"
echo "======================================="
echo ""

# Configuration
GITEA_URL="${GITEA_BASE_URL:-http://localhost:3000}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-admin}"

# Refuse to run with a default/baked-in password — historical default
# (admin123) has leaked into operator muscle memory and is easy to forget to
# replace. Force the operator to opt in explicitly.
if [ -z "${GITEA_ADMIN_PASSWORD:-}" ]; then
  echo "ERROR: GITEA_ADMIN_PASSWORD must be set" >&2
  exit 1
fi

DOMAIN="${GITEA_DOMAIN:-gogents.local}"

# Per-user output directory for credential and token files. Created with
# chmod 700 so other users on the host cannot read the freshly-minted tokens.
OUTPUT_DIR="${GOGENTS_OUTPUT_DIR:-$HOME/.config/gogents}"
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

CREDS_FILE="$OUTPUT_DIR/credentials.txt"
TOKENS_FILE="$OUTPUT_DIR/tokens.txt"
ENV_FILE="$OUTPUT_DIR/gitea-agents.env"
RESPONSE_FILE="$OUTPUT_DIR/.gitea_response.json"
TOKEN_RESPONSE_FILE="$OUTPUT_DIR/.token_response.json"

echo "📋 Configuration:"
echo "   Gitea URL: $GITEA_URL"
echo "   Admin User: $GITEA_ADMIN_USER"
echo "   Domain: $DOMAIN"
echo "   Output dir: $OUTPUT_DIR"
echo ""

# Check if Gitea is accessible
echo "🔍 Checking Gitea connectivity..."
if ! curl -s "$GITEA_URL/api/v1/version" > /dev/null; then
    echo "❌ Error: Cannot connect to Gitea at $GITEA_URL"
    echo "Please ensure Gitea is running and accessible."
    exit 1
fi
echo "✅ Gitea is accessible"
echo ""

# Define the 12 AI agents with their details
declare -A agents=(
    ["security"]="🔒 Security Agent - AI specialist in vulnerability detection and security analysis"
    ["performance"]="⚡ Performance Agent - AI specialist in optimization and algorithmic efficiency"
    ["architecture"]="🏗️ Architecture Agent - AI specialist in design patterns and software architecture"
    ["testing"]="🧪 Testing Agent - AI specialist in test coverage and quality assurance"
    ["compliance"]="⚖️ Compliance Agent - AI specialist in regulatory standards and compliance"
    ["accessibility"]="♿ Accessibility Agent - AI specialist in WCAG and accessibility standards"
    ["documentation"]="📚 Documentation Agent - AI specialist in code clarity and API documentation"
    ["maintainability"]="🔧 Maintainability Agent - AI specialist in long-term code health"
    ["business-logic"]="🎯 Business Logic Agent - AI specialist in requirements and domain correctness"
    ["dependencies"]="📦 Dependencies Agent - AI specialist in supply chain security"
    ["const"]="🔍 Const Agent - AI specialist in C++ const correctness and memory safety"
    ["style"]="🎨 Style Agent - AI specialist in code formatting and conventions"
)

# Function to generate a secure random password
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-12
}

# Function to register a user in Gitea
register_user() {
    local username=$1
    local email=$2
    local password=$3
    local full_name=$4

    echo "   Registering: $username"

    # Create user via Gitea admin API
    response=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
        -X POST "$GITEA_URL/api/v1/admin/users" \
        -H "Content-Type: application/json" \
        -u "$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD" \
        -d "{
            \"username\": \"$username\",
            \"email\": \"$email\",
            \"password\": \"$password\",
            \"full_name\": \"$full_name\",
            \"must_change_password\": false,
            \"send_notify\": false,
            \"source_id\": 0,
            \"login_name\": \"$username\"
        }")

    http_code="${response: -3}"

    if [ "$http_code" = "201" ]; then
        echo "   ✅ Created successfully"
        return 0
    elif [ "$http_code" = "422" ]; then
        # Check if user already exists
        if grep -q "username already exists" "$RESPONSE_FILE" 2>/dev/null; then
            echo "   ⚠️  User already exists, skipping"
            return 0
        else
            echo "   ❌ Registration failed: $(cat "$RESPONSE_FILE" 2>/dev/null)"
            return 1
        fi
    else
        echo "   ❌ HTTP Error $http_code: $(cat "$RESPONSE_FILE" 2>/dev/null)"
        return 1
    fi
}

# Function to create access token for user
create_access_token() {
    local username=$1
    local password=$2

    echo "   Creating access token for: $username"

    response=$(curl -s -w "%{http_code}" -o "$TOKEN_RESPONSE_FILE" \
        -X POST "$GITEA_URL/api/v1/users/$username/tokens" \
        -H "Content-Type: application/json" \
        -u "$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD" \
        -d "{
            \"name\": \"gogents-api-token\",
            \"scopes\": [\"write:repository\", \"write:issue\", \"read:user\"]
        }")

    http_code="${response: -3}"

    if [ "$http_code" = "201" ]; then
        token=$(jq -r '.sha1' "$TOKEN_RESPONSE_FILE" 2>/dev/null)
        if [ "$token" != "null" ] && [ -n "$token" ]; then
            echo "   ✅ Token created: ${token:0:8}..."
            echo "$username:$token" >> "$TOKENS_FILE"
            return 0
        fi
    fi

    echo "   ⚠️  Token creation failed, user can create manually"
    return 1
}

# Start registration process
echo "🚀 Starting agent registration..."
echo ""

# Create credentials file (mode 600 from umask)
cat > "$CREDS_FILE" << EOF
# GoGents AI Agent Credentials for Gitea
# Generated on $(date)
# Gitea URL: $GITEA_URL

EOF

# Create tokens file (mode 600 from umask)
echo "# GoGents AI Agent API Tokens" > "$TOKENS_FILE"
echo "# Format: username:token" >> "$TOKENS_FILE"

successful_registrations=0
failed_registrations=0

# Register each agent
for agent in "${!agents[@]}"; do
    username="gogents-$agent"
    email="$agent@$DOMAIN"
    password=$(generate_password)
    full_name="${agents[$agent]}"

    echo "👤 Agent: $agent"

    if register_user "$username" "$email" "$password" "$full_name"; then
        # Save credentials
        {
            echo ""
            echo "[$agent]"
            echo "Username: $username"
            echo "Email: $email"
            echo "Password: $password"
            echo "Full Name: $full_name"
        } >> "$CREDS_FILE"

        # Try to create access token
        create_access_token "$username" "$password" || true

        ((successful_registrations++))
    else
        ((failed_registrations++))
    fi

    echo ""
done

# Summary
echo "📊 Registration Summary:"
echo "========================"
echo "✅ Successful: $successful_registrations"
echo "❌ Failed: $failed_registrations"
echo "📁 Total Agents: ${#agents[@]}"
echo ""

if [ $successful_registrations -gt 0 ]; then
    echo "📄 Credentials saved to:"
    echo "   - $CREDS_FILE"
    echo "   - $TOKENS_FILE"
    echo ""

    echo "🔒 Sample credentials:"
    head -10 "$CREDS_FILE"
    echo "   ... (see full file for all agents)"
    echo ""

    # Create environment configuration
    echo "⚙️  Creating environment configuration..."
    cat > "$ENV_FILE" << EOF
# GoGents Gitea Agent Configuration
# Generated on $(date)

# Gitea Configuration
GITEA_BASE_URL=$GITEA_URL
GITEA_DOMAIN=$DOMAIN

# Agent Credentials (use individual tokens for production)
EOF

    # Add agent environment variables
    while IFS=: read -r username token; do
        if [[ "$username" =~ ^gogents- ]] && [ "$token" != "token" ]; then
            agent_name=$(echo "$username" | sed 's/gogents-//' | tr '-' '_' | tr '[:lower:]' '[:upper:]')
            echo "GITEA_${agent_name}_TOKEN=$token" >> "$ENV_FILE"
        fi
    done < "$TOKENS_FILE"

    echo "✅ Environment file created: $ENV_FILE"
    echo ""
fi

echo "🎯 Next Steps:"
echo "=============="
echo "1. Review credentials in $CREDS_FILE"
echo "2. Update email addresses in Gitea admin panel if needed"
echo "3. Copy $ENV_FILE to your GoGents configuration"
echo "4. Test agent access with: curl -H \"Authorization: token <TOKEN>\" $GITEA_URL/api/v1/user"
echo ""

if [ $failed_registrations -gt 0 ]; then
    echo "⚠️  Some registrations failed. Check Gitea logs and admin settings:"
    echo "   - Ensure user registration is enabled"
    echo "   - Check minimum password requirements"
    echo "   - Verify admin credentials are correct"
    echo ""
fi

echo "🎉 Agent registration process completed!"

# Cleanup intermediate response files (the credentials/tokens stay)
rm -f "$RESPONSE_FILE" "$TOKEN_RESPONSE_FILE"
