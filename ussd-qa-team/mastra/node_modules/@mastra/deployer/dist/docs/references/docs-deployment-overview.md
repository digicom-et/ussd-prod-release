# Deployment overview

Mastra applications can be deployed to any Node.js-compatible environment. You can deploy a Mastra server, integrate with an existing web framework, deploy to cloud providers, or use [Mastra platform](https://mastra.ai/docs/mastra-platform/overview) for observability, Studio, and server deployment.

## Runtime support

Mastra can run against any of these runtime environments:

- Node.js `v22.13.0` or later
- Bun
- Deno
- Cloudflare

## Deployment options

### Mastra server

Mastra provides a [server](https://mastra.ai/docs/server/mastra-server) powered by Hono that can be deployed independently. Use the `mastra build` command to build your application and deploy the output to your preferred VM, container, or PaaS platform.

Use this option when you need full control over your infrastructure, long-running processes, or WebSocket connections. The [Mastra server deployment guide](https://mastra.ai/docs/deployment/mastra-server) provides more details.

### Monorepo

Deploy a Mastra server as part of a monorepo setup, following the same approach as standalone deployment.

Read about [monorepo deployment](https://mastra.ai/docs/deployment/monorepo).

### Mastra platform

The [Mastra platform](https://mastra.ai/docs/mastra-platform/overview) provides three products for deploying, monitoring, and managing AI applications built with the Mastra framework:

- [**Observability**](https://mastra.ai/docs/mastra-platform/observability): A standalone hosted product for searchable traces, logs, and metrics across Mastra projects and deploys
- [**Studio**](https://mastra.ai/docs/mastra-platform/studio): A hosted visual environment for testing agents, running workflows, and inspecting traces
- [**Server**](https://mastra.ai/docs/mastra-platform/server): A production deployment target that runs your Mastra application as an API server

Learn more in the [Mastra platform overview](https://mastra.ai/docs/mastra-platform/overview).

### Cloud Providers

Mastra applications can be deployed to cloud providers and serverless platforms. Mastra includes optional built-in deployers for Vercel, Netlify, and Cloudflare to automate the build and deployment process.

Use this option for auto-scaling, minimal infrastructure management, or when you're already using one of these platforms.

- [Amazon EC2](https://mastra.ai/guides/deployment/amazon-ec2)
- [AWS Lambda](https://mastra.ai/guides/deployment/aws-lambda)
- [Azure App Services](https://mastra.ai/guides/deployment/azure-app-services)
- [Cloudflare](https://mastra.ai/guides/deployment/cloudflare)
- [Digital Ocean](https://mastra.ai/guides/deployment/digital-ocean)
- [Netlify](https://mastra.ai/guides/deployment/netlify)
- [Vercel](https://mastra.ai/guides/deployment/vercel)

### Web Framework

When Mastra is integrated with a web framework, it deploys alongside your application using the framework's standard deployment process. The guides below cover framework-specific configuration requirements for deployment.

Use these guides when adding Mastra to an existing Next.js or Astro application.

- [With Next.js on Vercel](https://mastra.ai/docs/deployment/web-framework)
- [With Astro on Vercel](https://mastra.ai/docs/deployment/web-framework)
- [With Astro on Netlify](https://mastra.ai/docs/deployment/web-framework)

## Workflow runners

Mastra workflows run using the built-in execution engine by default. For production workloads requiring managed infrastructure, workflows can also be deployed to specialized platforms like [Inngest](https://www.inngest.com) that provide step memoization, automatic retries, and real-time monitoring.

Visit the [Workflow Runners guide](https://mastra.ai/docs/deployment/workflow-runners) for execution options and the [Inngest deployment guide](https://mastra.ai/guides/deployment/inngest) for setup instructions.