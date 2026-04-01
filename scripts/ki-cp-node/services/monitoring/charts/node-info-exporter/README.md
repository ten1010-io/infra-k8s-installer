## 1. Cloning the Repository

### Using HTTPS
```bash
git clone https://github.com:ten1010-io/node-info-exporter-with-gpu.git
```

### Using SSH
```bash
git clone git@github.com:ten1010-io/node-info-exporter-with-gpu.git
```

<br>

## 2. Deploying with Helm

> [!warning] Warning  
> Must be install in the namespace registered to coaster `gpu_deactivation_except_ns`.

### Navigate to the Directory
```bash
cd node-info-exporter-with-gpu
```

### Preview the Chart
```bash
helm template <release-name> . --namespace <namespace>
```

### Install the Chart
```bash
helm install <release-name> . --namespace <namespace>
```

<br>

## 3. Verifying the Installation

### List Helm Releases
```bash
helm list -n <namespace>
```

### Check Release Status
```bash
helm status <release-name> -n <namespace>
```

<br>

## Upgrading the Helm Release

### Upgrade the Helm Release
```bash
helm upgrade <release-name> . --namespace <namespace>
```

### Use a Custom Values File (Optional)
```bash
helm upgrade <release-name> . --namespace <namespace> -f custom-values.yaml
```
