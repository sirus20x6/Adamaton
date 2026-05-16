# /thearray/gogents/docs/development/new-agents.md
## Adding New Agents

### Agent Development Process

#### 1. Plan the New Agent
Before implementing, consider:
- **Purpose**: What specific aspect of code quality will this agent analyze?
- **Scope**: What programming languages and file types will it support?
- **Complexity**: Should it use vLLM (complex analysis) or traditional logic (simple checks)?
- **Priority**: How important is this agent's verdict in the overall decision?

### Step-by-Step Implementation

#### Step 1: Define Agent Type
```go
// internal/types/agents.go
const (
    // Existing agents...
    AgentDocumentation AgentType = "documentation"  // Add new agent type
)

// Add to agent weight mapping
var AgentWeights = map[AgentType]float64{
    // Existing weights...
    AgentDocumentation: 1.0,  // Standard weight
}

// Add to required agents list (if applicable)
var RequiredAgents = []AgentType{
    AgentSecurity,
    AgentCompliance,
    AgentBusinessLogic,
    // AgentDocumentation,  // Uncomment if required
}
```

#### Step 2: Add System Prompt (vLLM Agents)
```go
// internal/llm/client.go - Add to buildAgentSystemPrompt()
case types.AgentDocumentation:
    return basePrompt + `You are a DOCUMENTATION EXPERT. Focus on:
- API documentation completeness and accuracy
- Code comment quality and clarity
- README and user guide adequacy
- Inline documentation for complex functions
- Example code and usage patterns
- Documentation consistency and standards
- Missing or outdated documentation`
```

#### Step 3: Create Activity Function
```go
// activities/pr_review_activities.go

// For vLLM-powered agents:
func DocumentationCheckActivity(ctx context.Context, diff string) (CheckResult, error) {
    // Enhanced diff analysis
    metrics := AnalyzeDiffEnhanced(diff)
    
    // Use vLLM client for analysis
    client := NewVLLMClient(VLLMEndpoint, 2*time.Minute, logger)
    
    config := types.AgentConfig{
        MaxTokens:   512,
        Temperature: 0.1,
    }
    
    result, err := client.ExecuteAgentAnalysis(ctx, types.AgentDocumentation, diff, config)
    if err != nil {
        // Fallback to traditional analysis
        return fallbackDocumentationCheck(diff, metrics)
    }
    
    // Attach metrics to result
    result.Metrics = metrics
    return result, nil
}

// For traditional logic agents:
func DocumentationCheckActivity(ctx context.Context, diff string) (CheckResult, error) {
    metrics := AnalyzeDiffEnhanced(diff)
    
    // Analyze documentation coverage
    issues := analyzeDocumentationCoverage(diff, metrics)
    
    verdict := "PASS"
    if len(issues) > 0 {
        verdict = "FAIL"
    }
    
    return CheckResult{
        Agent:     "Documentation",
        Verdict:   verdict,
        Rationale: buildDocumentationRationale(issues),
        Metrics:   metrics,
    }, nil
}

// Helper function for traditional analysis
func analyzeDocumentationCoverage(diff string, metrics *AnalysisMetrics) []string {
    var issues []string
    
    // Check for new public functions without documentation
    for _, function := range metrics.AffectedFunctions {
        if isPublicFunction(function) && !hasDocumentation(diff, function) {
            issues = append(issues, fmt.Sprintf("Public function %s lacks documentation", function))
        }
    }
    
    // Check for README updates when adding new features
    if hasNewFeatures(diff) && !hasREADMEUpdates(metrics.AffectedFiles) {
        issues = append(issues, "New features added but README not updated")
    }
    
    // Check for API changes without documentation updates
    if hasAPIChanges(diff) && !hasAPIDocUpdates(metrics.AffectedFiles) {
        issues = append(issues, "API changes detected but documentation not updated")
    }
    
    return issues
}
```

#### Step 4: Register Activity in Worker
```go
// workers/worker.go
func registerActivities(w worker.Worker) {
    // Enhanced Activities (vLLM-powered)
    w.RegisterActivity(activities.VLLMSecurityCheckActivity)
    w.RegisterActivity(activities.VLLMPerformanceCheckActivity)
    w.RegisterActivity(activities.VLLMArchitectureCheckActivity)
    w.RegisterActivity(activities.VLLMTestingCheckActivity)
    w.RegisterActivity(activities.VLLMComplianceCheckActivity)
    w.RegisterActivity(activities.VLLMAccessibilityCheckActivity)
    w.RegisterActivity(activities.DocumentationCheckActivity)  // Add new agent
    
    // Traditional Activities
    w.RegisterActivity(activities.ConstCheckActivity)
    w.RegisterActivity(activities.DependenciesCheckActivity)
    w.RegisterActivity(activities.MaintainabilityCheckActivity)
    w.RegisterActivity(activities.BusinessLogicCheckActivity)
    w.RegisterActivity(activities.StyleCheckActivity)
    
    // Core Activities
    w.RegisterActivity(activities.FetchDiffActivity)
    w.RegisterActivity(activities.MergeActivity)
    w.RegisterActivity(activities.CommentForHumanReviewActivity)
}
```

#### Step 5: Update Workflow
```go
// workflows/pr_review_workflow.go
func PRReviewWorkflow(ctx workflow.Context, args PRReviewArgs) error {
    // ... existing code ...
    
    // Execute all agents in parallel
    var (
        securityResult      CheckResult
        performanceResult   CheckResult
        architectureResult  CheckResult
        testingResult       CheckResult
        complianceResult    CheckResult
        accessibilityResult CheckResult
        documentationResult CheckResult  // Add new agent result
        constResult         CheckResult
        dependenciesResult  CheckResult
        maintainabilityResult CheckResult
        businessLogicResult CheckResult
        styleResult         CheckResult
    )
    
    // Create activity options
    ao := workflow.ActivityOptions{
        StartToCloseTimeout: 3 * time.Minute,
        RetryPolicy: &workflow.RetryPolicy{
            InitialInterval:    5 * time.Second,
            BackoffCoefficient: 2.0,
            MaximumInterval:    1 * time.Minute,
            MaximumAttempts:    3,
        },
    }
    ctx = workflow.WithActivityOptions(ctx, ao)
    
    // Execute all agents
    futures := []workflow.Future{
        workflow.ExecuteActivity(ctx, activities.VLLMSecurityCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.VLLMPerformanceCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.VLLMArchitectureCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.VLLMTestingCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.VLLMComplianceCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.VLLMAccessibilityCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.DocumentationCheckActivity, diff),  // Add new agent
        workflow.ExecuteActivity(ctx, activities.ConstCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.DependenciesCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.MaintainabilityCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.BusinessLogicCheckActivity, diff),
        workflow.ExecuteActivity(ctx, activities.StyleCheckActivity, diff),
    }
    
    // Wait for all results
    futures[0].Get(ctx, &securityResult)
    futures[1].Get(ctx, &performanceResult)
    futures[2].Get(ctx, &architectureResult)
    futures[3].Get(ctx, &testingResult)
    futures[4].Get(ctx, &complianceResult)
    futures[5].Get(ctx, &accessibilityResult)
    futures[6].Get(ctx, &documentationResult)  // Get new agent result
    futures[7].Get(ctx, &constResult)
    futures[8].Get(ctx, &dependenciesResult)
    futures[9].Get(ctx, &maintainabilityResult)
    futures[10].Get(ctx, &businessLogicResult)
    futures[11].Get(ctx, &styleResult)
    
    // Collect all results
    allResults := []CheckResult{
        securityResult,
        performanceResult,
        architectureResult,
        testingResult,
        complianceResult,
        accessibilityResult,
        documentationResult,  // Include new agent
        constResult,
        dependenciesResult,
        maintainabilityResult,
        businessLogicResult,
        styleResult,
    }
    
    // ... rest of workflow logic ...
}
```

#### Step 6: Add Tests
```go
// tests/unit/activities/documentation_test.go
func TestDocumentationCheckActivity(t *testing.T) {
    tests := []struct {
        name            string
        diff            string
        expectedVerdict string
        expectedContains string
    }{
        {
            name: "missing documentation for public function",
            diff: `+func ProcessUserData(user User) error {
+    return validateUser(user)
+}`,
            expectedVerdict: "FAIL",
            expectedContains: "lacks documentation",
        },
        {
            name: "well documented public function",
            diff: `+// ProcessUserData validates and processes user information
+// Returns error if validation fails
+func ProcessUserData(user User) error {
+    return validateUser(user)
+}`,
            expectedVerdict: "PASS",
            expectedContains: "",
        },
        {
            name: "private function without docs is ok",
            diff: `+func processInternal(data string) string {
+    return strings.ToUpper(data)
+}`,
            expectedVerdict: "PASS",
            expectedContains: "",
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result, err := DocumentationCheckActivity(context.Background(), tt.diff)
            assert.NoError(t, err)
            assert.Equal(t, tt.expectedVerdict, result.Verdict)
            if tt.expectedContains != "" {
                assert.Contains(t, result.Rationale, tt.expectedContains)
            }
        })
    }
}
```

#### Step 7: Update Documentation
```bash
# Update README.md agent count
# Update docs/main/ai-agents.md with new agent description
# Update Makefile agent-summary command
# Update PROJECT_STATUS.md metrics
```

### Agent Categories and Guidelines

#### vLLM-Enhanced Agents (Complex Analysis)
**Use for**: Subjective analysis requiring AI reasoning
- **Examples**: Security, Performance, Architecture, Compliance
- **Characteristics**: Complex prompts, contextual analysis, nuanced decisions
- **Implementation**: Use `client.ExecuteAgentAnalysis()` with fallback

#### Traditional Logic Agents (Rule-Based)
**Use for**: Objective checks with clear rules
- **Examples**: Style, Dependencies, Const Correctness
- **Characteristics**: Pattern matching, syntax checking, measurable criteria
- **Implementation**: Direct analysis with helper functions

### Advanced Agent Features

#### Context-Aware Analysis
```go
// Use repository context for better analysis
func buildDocumentationPrompt(diff string, metrics *AnalysisMetrics) string {
    languageContext := ""
    if len(metrics.Languages) > 0 {
        languageContext = "\nLanguages detected: "
        for lang := range metrics.Languages {
            languageContext += lang + " "
        }
    }
    
    return fmt.Sprintf(`[DOCUMENTATION AGENT]
Analyze this code change for documentation quality and completeness.
%s

Focus on:
- Public API documentation
- Code comment clarity
- README updates for new features
- Example usage documentation
- Consistency with existing documentation standards

<diff>
%s
</diff>`, languageContext, diff)
}
```

#### Configurable Agent Behavior
```go
// Allow per-repository agent configuration
type DocumentationConfig struct {
    RequirePublicFunctionDocs bool
    RequireREADMEUpdates     bool
    MinCommentLength         int
    ExcludeFilePatterns      []string
}

func loadAgentConfig(repoOwner, repoName string) DocumentationConfig {
    // Load from .gogents/documentation.yml or use defaults
    return DocumentationConfig{
        RequirePublicFunctionDocs: true,
        RequireREADMEUpdates:     true,
        MinCommentLength:         20,
        ExcludeFilePatterns:      []string{"*.test.go", "vendor/*"},
    }
}
```

### Testing New Agents

#### Unit Testing
```bash
# Test individual agent
go test -v ./activities/ -run TestDocumentationCheckActivity

# Test with different scenarios
go test -v ./activities/ -run TestDocumentation
```

#### Integration Testing
```bash
# Test agent in workflow
make enhanced-demo

# Test with real PR
./bin/start_workflow --pr 123 --owner test --repo documentation-test
```

#### Performance Testing
```bash
# Benchmark new agent
go test -bench=BenchmarkDocumentationAgent ./tests/performance/
```

### Best Practices

1. **Clear Purpose**: Each agent should have a specific, well-defined responsibility
2. **Consistent Interface**: Follow existing patterns for activity signatures
3. **Comprehensive Testing**: Test both positive and negative cases
4. **Performance Awareness**: Consider impact on overall review time
5. **Fallback Logic**: Provide graceful degradation if external services fail
6. **Documentation**: Update all relevant documentation when adding agents
7. **Configuration**: Make agent behavior configurable when appropriate
