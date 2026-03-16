# Deployment Guide

## Minikube starten
minikube start --cpus=4 --memory=8192

## Deployment anwenden
kubectl apply -k kustomize/overlays/minikube

## Argo CD Applications
kubectl apply -f argocd/zookeeper.yaml
kubectl apply -f argocd/solr.yaml
