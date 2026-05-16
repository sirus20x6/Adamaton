# /thearray/gogents/docs/main/web-dashboard.md
## Web Dashboard

### Interactive Dashboard
Access the main dashboard at **http://localhost:9123/dashboard.html**

- **System Status**: Real-time service health monitoring
- **Active Workflows**: Live PR review progress tracking
- **Agent Performance**: Individual agent success rates and timing
- **Queue Status**: Temporal task queue depth and processing rates
- **Quick Actions**: Start workflows, manage workers, view metrics

### Performance Monitor
Access performance analytics at **http://localhost:9123/performance.html**

- **Real-time Metrics**: Live system performance tracking
- **Historical Trends**: Performance over time with interactive charts
- **Resource Utilization**: CPU, memory, and network usage
- **Agent Analytics**: Detailed per-agent performance breakdown
- **Alerting**: Visual alerts for system issues

### Features
- **Real-time Updates**: Live data refresh without page reload
- **Interactive Charts**: Click to drill down into specific metrics
- **Responsive Design**: Mobile-friendly interface
- **Export Data**: Download metrics as JSON for analysis
- **Theme Support**: Light/dark mode toggle

### API Integration
The dashboard connects to the REST API at **http://localhost:9123/api/v1/** for:
- System health checks
- Workflow management
- Performance metrics
- Configuration status
