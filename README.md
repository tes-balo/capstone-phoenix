# 🚀 Capstone Phoenix — Production-Ready Kubernetes Platform on Azure

> **DevOps Capstone Project for TSAcademy**
>
> This repository contains my end-to-end implementation of a production-style Kubernetes platform deployed on Microsoft Azure. The project provisions infrastructure using Terraform, configures a highly available Kubernetes cluster with Ansible and k3s, deploys a full-stack TaskApp using Kubernetes manifests, and manages the entire application lifecycle through GitOps with Argo CD and automated CI/CD pipelines.

> **Note:** This repository is a fork of the official TSAcademy Capstone repository. While the assignment specification originated from the upstream repository, all infrastructure provisioning, Kubernetes configuration, GitOps implementation, CI/CD automation, documentation, troubleshooting, and deployment decisions in this repository represent my own implementation.

---

# Table of Contents

* Project Overview
* Objectives
* Solution Architecture
* Technology Stack
* Repository Structure
* Infrastructure
* Kubernetes Platform
* Application Deployment
* GitOps
* CI/CD Pipeline
* Security
* High Availability
* Live Endpoints
* Project Features
* Challenges & Lessons Learned
* Future Improvements
* Documentation
* Acknowledgements

---

# Project Overview

The objective of this capstone was to deploy the TaskApp application onto a real multi-node Kubernetes cluster using modern DevOps practices instead of deploying a container directly to a single virtual machine.

The final solution provisions cloud infrastructure automatically, configures the Kubernetes cluster without manual intervention, deploys the application using declarative manifests, secures traffic with HTTPS certificates from Let's Encrypt, stores secrets securely using Sealed Secrets, and manages deployments through GitOps using Argo CD.

The project demonstrates the complete DevOps lifecycle—from infrastructure provisioning to automated application delivery.

---

# Objectives

This project demonstrates:

* Infrastructure as Code (Terraform)
* Configuration Management (Ansible)
* Kubernetes orchestration
* High Availability deployments
* GitOps using Argo CD
* Continuous Integration & Continuous Deployment
* Secret management
* HTTPS with automatic certificate management
* Production deployment practices
* Cloud networking and security

---

# Solution Architecture

```
                        GitHub

                           │
                 GitHub Actions CI/CD
                           │
                 Build & Push Images
                           │
                         GHCR
                           │
             Update Kubernetes Manifests
                           │
                       Argo CD
                           │
                   Kubernetes Cluster
                           │
                     Traefik Ingress
                ┌──────────┴──────────┐
                │                     │
          Frontend Service      Backend Service
                │                     │
          Frontend Pods        Backend Pods
                                      │
                               PostgreSQL
                               StatefulSet
                                      │
                                     PVC

────────────────────────────────────────────────────

Infrastructure

Terraform
        │
Azure Resource Group
        │
Virtual Network
        │
Subnet
        │
Network Security Group
        │
3 Ubuntu Virtual Machines
        │
Ansible
        │
k3s Cluster
```

---

# Technology Stack

## Cloud

* Microsoft Azure
* Azure Virtual Machines
* Azure Virtual Network
* Azure Network Security Groups

## Infrastructure

* Terraform
* Ansible

## Container Platform

* Kubernetes (k3s)
* Calico CNI
* Traefik Ingress Controller

## GitOps

* Argo CD

## Security

* cert-manager
* Let's Encrypt
* Sealed Secrets

## CI/CD

* GitHub Actions
* GitHub Container Registry (GHCR)

## Application

* React Frontend
* Flask Backend
* PostgreSQL

---

# Repository Structure

```
capstone-phoenix/

├── infra/
│   ├── terraform/
│   └── ansible/
│
├── manifests/
│
├── gitops/
│
├── docs/
│
└── README.md
```

---

# Infrastructure

Infrastructure is provisioned entirely using Terraform.

Resources include:

* Resource Group
* Virtual Network
* Subnet
* Network Security Group
* Public IP Addresses
* Network Interfaces
* Three Ubuntu Virtual Machines

Cluster topology:

* 1 Control Plane
* 2 Worker Nodes

The infrastructure is modularized into:

* Network module
* Security module
* Compute module

---

# Kubernetes Platform

The Kubernetes platform is built using k3s.

Components deployed include:

* Traefik Ingress Controller
* Calico CNI
* cert-manager
* Sealed Secrets
* Argo CD

Application resources include:

* Namespace
* ConfigMap
* Sealed Secret
* PostgreSQL StatefulSet
* Backend Deployment
* Frontend Deployment
* Migration Job
* Services
* Ingress

---

# GitOps

The cluster follows a GitOps workflow.

GitHub is the single source of truth.

Argo CD continuously watches this repository and automatically reconciles cluster state whenever changes are pushed.

Features include:

* Automatic Synchronization
* Self Healing
* Automatic Pruning

No manual `kubectl apply` is required after bootstrap.

---

# Continuous Integration & Continuous Deployment

Separate repositories are used for the frontend and backend applications.

Each application includes GitHub Actions workflows that:

* Run tests
* Build Docker images
* Push images to GHCR
* Update Kubernetes manifests
* Commit image tag changes

Argo CD detects the updated manifests and deploys the new version automatically.

Deployment pipeline:

```
Developer Push

↓

GitHub Actions

↓

Docker Build

↓

GHCR

↓

Update Manifest

↓

Git Commit

↓

Argo CD Sync

↓

Kubernetes Rolling Update
```

---

# Security

Implemented security features include:

* HTTPS using Let's Encrypt
* cert-manager certificate automation
* Sealed Secrets
* Resource limits
* Liveness probes
* Readiness probes
* Topology spread constraints
* Network Security Groups
* SSH key authentication
* Non-root administration user

---

# High Availability

The application has been designed with availability in mind.

Features include:

* Three-node Kubernetes cluster
* Multiple frontend replicas
* Multiple backend replicas
* Rolling updates
* Topology Spread Constraints
* Persistent PostgreSQL storage
* Kubernetes Services for load balancing

---

# Live Endpoints

| Service     | URL                           |
| ----------- | ----------------------------- |
| Frontend    | https://taskapp.tesbuilds.fun |
| Backend API | https://api.tesbuilds.fun     |
| Argo CD     | https://argocd.tesbuilds.fun  |

---

# Project Features

Implemented:

* Terraform Infrastructure
* Ansible Cluster Provisioning
* k3s Kubernetes Cluster
* Calico Networking
* Traefik Ingress
* cert-manager
* Let's Encrypt
* Sealed Secrets
* PostgreSQL StatefulSet
* Migration Job
* Multi-replica Deployments
* GitOps
* GitHub Actions CI/CD
* Rolling Updates
* Health Probes
* Resource Limits

Planned improvements:

* Horizontal Pod Autoscaler
* Network Policies
* Pod Disruption Budgets
* Monitoring with Prometheus & Grafana

---

# Challenges & Lessons Learned

Some of the most significant engineering challenges encountered during the project included:

* Azure dropping Calico IPIP traffic, requiring migration to VXLAN.
* Understanding GitOps reconciliation and the bootstrap problem.
* Configuring Argo CD behind Traefik with HTTPS.
* Secure secret management using Sealed Secrets.
* Automating application deployment through GitHub Actions.
* Debugging Kubernetes networking across multiple worker nodes.
* Migrating from AWS to Azure while adapting infrastructure patterns.

Each challenge strengthened my understanding of cloud-native infrastructure and production Kubernetes operations.

---

# Documentation

Additional documentation is available in the `docs` directory.

* `ARCHITECTURE.md`
* `RUNBOOK.md`
* `COST.md`
* `EVIDENCE/`

---

# Future Improvements

Future enhancements include:

* Horizontal Pod Autoscaler
* Pod Disruption Budgets
* Network Policies
* Prometheus & Grafana Monitoring
* Automated PostgreSQL Backups
* Disaster Recovery Automation
* Multi-control-plane Kubernetes
* Managed Database Services

---

# Acknowledgements

This project was completed as part of the TSAcademy DevOps Program.

The application images and project brief were provided by TSAcademy. The cloud infrastructure, Kubernetes platform, GitOps implementation, CI/CD automation, documentation, and deployment architecture contained in this repository were designed and implemented as part of my capstone submission.

---

**Author**

**Teslim Balogun**

Software Developer | DevOps Engineer

GitHub: https://github.com/tes-balo
