# helm repo add langfuse https://langfuse.github.io/langfuse-k8s

# helm repo update

helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update
helm install langfuse langfuse/langfuse -f values.yaml
