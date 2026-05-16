### 🔴 Critical Agents (Weight: 2.0, Required)
1. **🔒 Security Agent** - Vulnerability detection and exploit prevention *(vLLM-powered)*
2. **⚖️ Compliance Agent** - Regulatory standards (GDPR, HIPAA, PCI DSS, SOX) *(vLLM-powered)*
3. **🎯 Business Logic Agent** - Requirements adherence and domain correctness

### 🟠 Important Agents (Weight: 1.5)
4. **⚡ Performance Agent** - Algorithmic complexity and optimization *(vLLM-powered)*
5. **🧪 Testing Agent** - Coverage analysis and quality assurance *(vLLM-powered)*
6. **🏗️ Architecture Agent** - Design patterns and SOLID principles *(vLLM-powered)*
7. **📦 Dependencies Agent** - Supply chain security and vulnerabilities
8. **🔧 Maintainability Agent** - Long-term code health and technical debt

### 🟡 Standard Agents (Weight: 1.0)
9. **📚 Documentation Agent** - API documentation and code clarity
10. **♿ Accessibility Agent** - WCAG compliance and inclusive design *(vLLM-powered)*
11. **🔍 Const Agent** - C++ const correctness and memory safety

### 🟢 Style Agent (Weight: 0.5)
12. **🎨 Style Agent** - Code formatting and convention adherence

**🚀 Enhanced with vLLM**: 6 agents now use **vLLM's OpenAI-compatible chat API** for improved analysis with optimized system prompts and structured response parsing.

**Key Enhancements**:
- **Unified LLM Interface** - Seamless backend switching (vLLM, OpenAI, Anthropic)
- **Smart Fallback System** - Automatic fallback to original implementation if vLLM fails
- **Advanced Prompt Engineering** - Specialized system prompts per agent type
- **Structured Response Parsing** - Consistent VERDICT/CONFIDENCE/SEVERITY format
- **Performance Optimization** - Parallel processing with configurable token limits
- **Health Monitoring** - Real-time vLLM server status and model information

Each agent returns structured results with **confidence levels** (0.0-1.0) and **severity ratings** (LOW/MEDIUM/HIGH/CRITICAL).
