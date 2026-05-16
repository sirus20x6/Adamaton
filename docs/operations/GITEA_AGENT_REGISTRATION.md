# /thearray/gogents/docs/GITEA_AGENT_REGISTRATION.md - Manual agent registration guide
# Gitea Agent Registration Guide

## 🤖 Registering 12 AI Agents in Gitea

Each GoGents AI agent needs its own Gitea user account to post reviews and comments. Here's how to register them:

## 🚀 Automated Registration (Recommended)

```bash
cd /thearray/gogents
chmod +x scripts/register-gitea-agents.sh

# Configure your Gitea settings
export GITEA_BASE_URL="http://your-gitea.local:3000"
export GITEA_ADMIN_USER="admin"
export GITEA_ADMIN_PASSWORD="your-admin-password"
export GITEA_DOMAIN="your-company.com"

# Run the registration script
./scripts/register-gitea-agents.sh
```

## 👥 Agent Details

The script will create these 12 users:

| Agent | Username | Email | Role |
|-------|----------|-------|------|
| 🔒 Security | `gogents-security` | security@your-domain.com | Vulnerability detection |
| ⚡ Performance | `gogents-performance` | performance@your-domain.com | Optimization analysis |
| 🏗️ Architecture | `gogents-architecture` | architecture@your-domain.com | Design patterns |
| 🧪 Testing | `gogents-testing` | testing@your-domain.com | Test coverage |
| ⚖️ Compliance | `gogents-compliance` | compliance@your-domain.com | Regulatory standards |
| ♿ Accessibility | `gogents-accessibility` | accessibility@your-domain.com | WCAG compliance |
| 📚 Documentation | `gogents-documentation` | documentation@your-domain.com | Code clarity |
| 🔧 Maintainability | `gogents-maintainability` | maintainability@your-domain.com | Code health |
| 🎯 Business Logic | `gogents-business-logic` | business-logic@your-domain.com | Domain correctness |
| 📦 Dependencies | `gogents-dependencies` | dependencies@your-domain.com | Supply chain security |
| 🔍 Const | `gogents-const` | const@your-domain.com | C++ const correctness |
| 🎨 Style | `gogents-style` | style@your-domain.com | Code formatting |

## 📋 Manual Registration Process

If you prefer to register manually or the script needs adjustments:

### Step 1: Access Gitea Admin Panel
1. Login to Gitea as administrator
2. Go to **Site Administration** → **User Accounts**
3. Click **Create User Account**

### Step 2: Create Each Agent User
For each of the 12 agents, create a user with:

**Example for Security Agent:**
- **Username**: `gogents-security`
- **Email**: `security@your-company.com`
- **Password**: `SecurePass123!` (use strong passwords)
- **Full Name**: `🔒 Security Agent - AI specialist in vulnerability detection`
- **Disable**: Leave unchecked
- **Admin**: Leave unchecked
- **Restricted**: Leave unchecked

### Step 3: Create API Tokens
For each agent user:
1. Login as the agent user (or use admin to impersonate)
2. Go to **Settings** → **Applications** → **Access Tokens**
3. Create new token with:
   - **Name**: `gogents-api-token`
   - **Scopes**: Select:
     - `write:repository` (to merge PRs)
     - `write:issue` (to comment on PRs)
     - `read:user` (to read user info)

### Step 4: Save Credentials
Keep track of all usernames, passwords, and tokens:

```
# Security Agent
Username: gogents-security
Email: security@your-company.com
Password: [your-secure-password]
Token: [generated-api-token]

# Performance Agent
Username: gogents-performance
Email: performance@your-company.com
Password: [your-secure-password] 
Token: [generated-api-token]

# ... (repeat for all 12 agents)
```

## ⚙️ Configuration

### Update GoGents Configuration
Add agent credentials to your GoGents configuration:

```bash
# /etc/gogents/gitea-agents.env

# Gitea Configuration
GITEA_BASE_URL=http://your-gitea.local:3000
GITEA_TIMEOUT=30s

# Individual Agent Tokens
GITEA_SECURITY_TOKEN=your-security-agent-token
GITEA_PERFORMANCE_TOKEN=your-performance-agent-token
GITEA_ARCHITECTURE_TOKEN=your-architecture-agent-token
GITEA_TESTING_TOKEN=your-testing-agent-token
GITEA_COMPLIANCE_TOKEN=your-compliance-agent-token
GITEA_ACCESSIBILITY_TOKEN=your-accessibility-agent-token
GITEA_DOCUMENTATION_TOKEN=your-documentation-agent-token
GITEA_MAINTAINABILITY_TOKEN=your-maintainability-agent-token
GITEA_BUSINESS_LOGIC_TOKEN=your-business-logic-agent-token
GITEA_DEPENDENCIES_TOKEN=your-dependencies-agent-token
GITEA_CONST_TOKEN=your-const-agent-token
GITEA_STYLE_TOKEN=your-style-agent-token
```

### Update GoGents Code
Modify the Gitea integration to use specific agent tokens:

```go
// Example: Use Security Agent for security-related comments
func (g *GiteaClient) PostSecurityComment(prNumber int, comment string) error {
    token := os.Getenv("GITEA_SECURITY_TOKEN")
    return g.postCommentAsAgent(prNumber, comment, token)
}
```

## 🔍 Testing Agent Access

Test each agent's access:

```bash
# Test Security Agent
curl -H "Authorization: token YOUR_SECURITY_TOKEN" \
  http://your-gitea.local:3000/api/v1/user

# Test Performance Agent  
curl -H "Authorization: token YOUR_PERFORMANCE_TOKEN" \
  http://your-gitea.local:3000/api/v1/user

# ... (test all agents)
```

## 🔒 Security Considerations

### Token Management
- **Unique Tokens**: Each agent has its own API token
- **Scope Limitation**: Tokens only have necessary permissions
- **Rotation**: Regularly rotate tokens for security
- **Storage**: Store tokens securely in environment variables

### User Permissions
- **No Admin Rights**: Agents should not have admin privileges
- **Repository Access**: Grant access only to repositories they need to review
- **Rate Limiting**: Monitor API usage to prevent abuse

### Audit Trail
- **Separate Users**: Each agent action is clearly attributed
- **Comment History**: All agent comments are tracked
- **Review Decisions**: Audit trail for merge/block decisions

## 🎯 Integration with GoGents

### Workflow Integration
```go
// Example workflow using multiple agents
func (w *GitReviewWorkflow) ExecuteAgents(ctx workflow.Context, diff string) []AgentResult {
    var results []AgentResult
    
    // Execute each agent with their specific credentials
    futures := []workflow.Future{
        workflow.ExecuteActivity(ctx, w.SecurityAgent.Analyze, diff),
        workflow.ExecuteActivity(ctx, w.PerformanceAgent.Analyze, diff),
        workflow.ExecuteActivity(ctx, w.ArchitectureAgent.Analyze, diff),
        // ... all 12 agents
    }
    
    // Collect results
    for i, future := range futures {
        var result AgentResult
        future.Get(ctx, &result)
        results = append(results, result)
    }
    
    return results
}
```

### Comment Attribution
Each agent's comments will be clearly attributed:

```markdown
**🔒 Security Agent Review**

I found 2 security vulnerabilities in this PR:

1. **SQL Injection** (Line 42): Direct string concatenation in query
2. **XSS Risk** (Line 89): Unescaped user input in HTML

Recommendation: Use parameterized queries and escape HTML output.

---
*This review was posted by GoGents Security Agent*
```

## 🚀 Next Steps

1. **Run Registration**: Execute the automated script or register manually
2. **Update Configuration**: Add agent tokens to GoGents config
3. **Test Integration**: Verify agents can access Gitea API
4. **Deploy**: Update GoGents deployment with agent credentials
5. **Monitor**: Watch agent activity in Gitea admin panel

## 🔧 Troubleshooting

### Common Issues
- **Registration Fails**: Check Gitea allows user registration
- **Token Creation Fails**: Verify admin permissions
- **API Access Denied**: Check token scopes and repository permissions
- **Rate Limiting**: Monitor API usage and adjust if needed

### Debug Commands
```bash
# Check Gitea API access
curl -v http://your-gitea.local:3000/api/v1/version

# Test agent authentication
curl -H "Authorization: token TOKEN" \
  http://your-gitea.local:3000/api/v1/user

# List user's repositories
curl -H "Authorization: token TOKEN" \
  http://your-gitea.local:3000/api/v1/user/repos
```

---

**🎉 With all 12 agents registered, GoGents can provide comprehensive, attributed AI code reviews in your self-hosted Gitea environment!**
