# Contributing to OpenStack Native

Thank you for your interest in contributing to OpenStack Native! This document provides guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please be respectful and professional in all interactions.

## Getting Started

### Prerequisites

- Kubernetes cluster (v1.28+)
- `kubectl` configured
- `git` installed
- Basic knowledge of Kubernetes, OpenStack, and ArgoCD

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork:

```bash
git clone https://github.com/YOUR_USERNAME/openstack-native.git
cd openstack-native
```

3. Add upstream remote:

```bash
git remote add upstream https://github.com/ams0/openstack-native.git
```

## How to Contribute

### Reporting Bugs

- Check if the bug has already been reported in [Issues](https://github.com/ams0/openstack-native/issues)
- If not, create a new issue with:
  - Clear title and description
  - Steps to reproduce
  - Expected vs actual behavior
  - Environment details (Kubernetes version, etc.)
  - Relevant logs or screenshots

### Suggesting Enhancements

- Check if the enhancement has been suggested
- Create a new issue describing:
  - Use case and motivation
  - Proposed solution
  - Alternative solutions considered
  - Impact on existing functionality

### Contributing Code

We welcome contributions for:

- Bug fixes
- New features
- Documentation improvements
- Test coverage
- Performance improvements
- Security enhancements

## Development Workflow

### 1. Create a Branch

```bash
# Update your fork
git checkout main
git pull upstream main

# Create a feature branch
git checkout -b feature/your-feature-name
```

### 2. Make Changes

- Write clear, concise commit messages
- Follow coding standards
- Add tests for new functionality
- Update documentation

### 3. Test Your Changes

```bash
# Validate YAML syntax
for file in $(find . -name "*.yaml" -o -name "*.yml"); do
  python3 -c "import yaml; yaml.safe_load(open('$file'))"
done

# Validate Kustomize builds
kubectl kustomize manifests/base/infra
kubectl kustomize manifests/overlays/production/infra

# Test deployment (if you have a cluster)
./scripts/deploy.sh
./scripts/check-health.sh
```

### 4. Commit Your Changes

```bash
git add .
git commit -m "Add feature: brief description

Detailed description of what changed and why.

Fixes #123"
```

### 5. Push to Your Fork

```bash
git push origin feature/your-feature-name
```

### 6. Create a Pull Request

1. Go to your fork on GitHub
2. Click "New Pull Request"
3. Select your feature branch
4. Fill in the PR template:
   - Description of changes
   - Related issues
   - Testing performed
   - Screenshots (if applicable)

## Coding Standards

### Kubernetes Manifests

- Use consistent indentation (2 spaces)
- Include labels and annotations:
  ```yaml
  metadata:
    labels:
      app: service-name
      app.kubernetes.io/name: service-name
      app.kubernetes.io/part-of: openstack
  ```
- Define resource limits and requests
- Include health checks (liveness, readiness)
- Use meaningful names

### Kustomize

- Use modern syntax (`resources` instead of `bases`)
- Organize overlays by environment
- Use patches for environment-specific changes
- Keep base manifests generic

### ArgoCD Applications

- Enable automated sync
- Configure sync policies
- Add retry backoff
- Use appropriate sync options

### Shell Scripts

- Include shebang: `#!/bin/bash`
- Use `set -e` for error handling
- Add comments for complex logic
- Use meaningful variable names
- Make scripts executable: `chmod +x script.sh`

### Documentation

- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Keep README up to date
- Document configuration options

## Testing

### Manual Testing

Test your changes in a real Kubernetes cluster:

```bash
# Deploy your changes
kubectl apply -f argocd/openstack-root-app.yaml

# Monitor deployment
kubectl get applications -n argocd
kubectl get pods -n openstack-infra
kubectl get pods -n openstack

# Check logs
kubectl logs -n openstack deployment/keystone

# Run health checks
./scripts/check-health.sh
```

### Validation Testing

```bash
# Validate YAML syntax
yamllint manifests/

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f manifests/

# Validate Kustomize builds
kubectl kustomize manifests/overlays/production/infra
```

### Cleanup

```bash
./scripts/cleanup.sh
```

## Documentation

### Documentation Updates

When making changes, update relevant documentation:

- **README.md**: Overview, quick start, features
- **docs/ARCHITECTURE.md**: Architecture changes
- **docs/DEPLOYMENT.md**: Deployment procedures
- **Code comments**: Inline documentation

### Writing Documentation

- Use Markdown format
- Include code examples
- Add diagrams using Mermaid or ASCII art
- Keep it up to date with code changes
- Check spelling and grammar

## Submitting Changes

### Pull Request Guidelines

- **Title**: Brief, descriptive title
- **Description**: 
  - What changed
  - Why it changed
  - How to test
  - Related issues
- **Testing**: Describe testing performed
- **Documentation**: Confirm docs are updated
- **Breaking Changes**: Clearly mark any breaking changes

### PR Review Process

1. Automated checks run
2. Maintainers review code
3. Address feedback
4. Approval from maintainers
5. Merge to main branch

### After Merge

- Delete your feature branch
- Update your fork:
  ```bash
  git checkout main
  git pull upstream main
  git push origin main
  ```

## Commit Message Format

Use conventional commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Build process or auxiliary tool changes

**Examples:**

```
feat(keystone): add support for LDAP authentication

Implements LDAP authentication backend for Keystone.
Includes configuration options and documentation.

Fixes #42
```

```
fix(mariadb): correct persistent volume size

Updates MariaDB PVC size from 50Gi to 100Gi to prevent
storage issues in production deployments.

Closes #56
```

## Code Review Guidelines

### For Contributors

- Be responsive to feedback
- Be patient during review
- Ask questions if unclear
- Update PR based on feedback

### For Reviewers

- Be constructive and respectful
- Explain reasoning for suggestions
- Approve when satisfied
- Test changes when possible

## Community

### Getting Help

- **GitHub Discussions**: Ask questions, share ideas
- **GitHub Issues**: Report bugs, request features
- **Pull Requests**: Submit code changes

### Communication

- Be respectful and professional
- Stay on topic
- Help others when you can
- Share your knowledge

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Recognition

Contributors will be recognized in:
- GitHub contributors page
- Release notes (for significant contributions)
- Project documentation (for major features)

## Questions?

If you have questions about contributing, please:

1. Check existing documentation
2. Search closed issues
3. Ask in GitHub Discussions
4. Open a new issue

Thank you for contributing to OpenStack Native! 🎉
