# AKS Cluster
<!-- ## Productivity setup in VS Code in Mac to avoid write "kubectl" everytime:
Writing `kubectl` everytime in console takes some time, so we configure to use the alias `k` to save some time:
```
# enable zsh completion (once)
autoload -Uz compinit
compinit

# kubectl completion for zsh
source <(kubectl completion zsh)

# alias: use k instead of kubectl
alias k=kubectl
# make k use the same completion as kubectl
compdef k=kubectl
```

Finally, reload your shell:
```
source ~/.zshrc
``` -->


## Before Cluster & Infrastructure Applications are created
### Connecting to the Azure AKS Cluster
According azure documentation we have to use this first command:
```
az account set --subscription <AZURE-SUBSCRIPTION-NUMBER>
```


### AKS Kubeconfig file:
We can create a separate Kubeconfig file for this new AKS Cluster (in this example I call the Kubeconfig file `aks-dev`), in order to add some order.

So every time you want to use this specific kubeconfig file you have to export it in the console using:
```
export KUBECONFIG=~/.kube/aks-dev
```

Finally, to verify you are in the right kubeconfig, check it using this command:
```
kubectl config view
```

Or also visit the local Path `/Users/<YOUR-USERNAME>/.kube` to see the kubeconfig files available.



## Executing Terraform Apply in parts:
To use terraform apply in Azure we have to mention in the terraform code the `subscription_id`, so we use this command before `terraform plan`: 
```
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "$ARM_SUBSCRIPTION_ID"
```

### PART1: This builds the RG + cluster only.
And after this, when we want to run `terraform plan` or `terraform apply` we use the respective env. name (`dev` or `prod`), for example:
```
terraform plan 

terraform apply
```

### PART2: Connecting to the Azure AKS Cluster, & put the new AKS context into your dedicated kubeconfig file
After the AKS Cluster is created, you can run this command in your terminal to get and merge your specific credential located in ~/.kube/aks-dev:
```
az aks get-credentials \
  --resource-group aks-terraform-rg \
  --name aks-terraform \
  --file ~/.kube/aks-dev \
  --overwrite-existing

kubectl --kubeconfig ~/.kube/aks-dev get nodes        # just as sanity check
```

### PART3: Run Terraform again with the flag to enable Infrastructure Applications (Nginx Ingress & ArgoCD):
Now that the Cluster is created and the AKS context is into your dedicated kubeconfig file, install through Terraform the Infrastructure Applications:
```
terraform apply -var="install_helmcharts=true"
```



## Using K9S
If you wanna use K9S, you have can run the program using a custom kubeconfig (in this example I call the Kubeconfig file `aks-dev`):
```
k9s --kubeconfig ~/.kube/aks-dev
```



## Login to ArgoCD application:
To access ArgoCD you have to add in your local `/etc/hosts` the `ingress_nginx_external_IP` that terraform outputs and the `host url`, it normally you will write this line in this structure: 
```
<TERRAFORM-OUTPUT-IP>     argocd.aks-terraform.westeurope.cloudapp.azure.com/applications

```

Once you access the ARGO CD login screen using the URL: argocd.aks-terraform.westeurope.cloudapp.azure.com

you have to run this command to get the `initial admin password`:
```
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

And for the User in the ArgoCD login page write the default value: `admin`



## Deploying using Helmcharts (no OCI) into ArgoCD (Example, installing WORDPRESS):
To start deploying fast we use this Helmcharts (avoid Bitnami charts): https://artifacthub.io/
Please refer this good youtuber videoguide:  https://youtu.be/m6e0WvkR4fY?si=kuecDmIU9-LTAi9k&t=274

### Add the repository using Argocd UI:
In Settings > Repositories > Connect Repo, fill these values:
- Type: Helm
- Name: groundhog2k
- URL: https://groundhog2k.github.io/helm-charts/


### Create the app "as YAML code" option using ArgoCD UI:
To avoid Argocd UI bugs, better add the YAML code and create the app. For example for WORDPRESS the yaml code is:
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: wordpress
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://groundhog2k.github.io/helm-charts/
    chart: wordpress
    targetRevision: 0.14.3   # pick a stable version from the repo
    helm:
      releaseName: wordpress
      values: |
        ingress:
          enabled: true
          className: nginx
          annotations:
            kubernetes.io/ingress.class: nginx
            nginx.ingress.kubernetes.io/rewrite-target: /
          hosts:
            - host: wordpress.aks-terraform.westeurope.cloudapp.azure.com   #verify this
              paths:
                - path: /
                  pathType: Prefix
          tls:
            - hosts:
                - wordpress.aks-terraform.westeurope.cloudapp.azure.com
              secretName: wordpress-tls

        service:
          type: ClusterIP

        persistence:
          enabled: true
          storageClass: managed-csi
          accessModes: ["ReadWriteOnce"]
          size: 10Gi

        mariadb:
          enabled: true
          settings:
            rootPassword: "SuperStrongRoot123!"
          userDatabase:
            name: wordpress
            user: wp  
            password: "SuperStrongApp123!"

  destination:
    server: https://kubernetes.default.svc
    namespace: wordpress

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```


Finally, due to Ingress changes were added in the yaml code above, to access in the browser to Wordpress as part of this example, you need to add an extra line in your /etc/hosts file:
```
<TERRAFORM-OUTPUT-IP>     wordpress.aks-terraform.westeurope.cloudapp.azure.com/applications

```



## Deploying apps using OCI from Artifacthub.io into ARGOCD (Example, installing REDIS):
### Enabling the use of OCI in ArgoCD
First you need to enable the use of OCI in ArgoCD adding in its configmap using this command 
```
kubectl edit configmap argocd-cm -n argocd
```

Inside this config Map ADD this extra line below `data` section:
```
data:
  helm.oci.enabled: "true"
```

Finally, restart ArgoCD server with
```
kubectl rollout restart deployment argocd-server -n argocd
```

### Add the repository using Argocd CLI (because of ArgoCD UI bugs)
First login in your terminal to argoCD CLI using 
```
argocd login argocd.aks-terraform.westeurope.cloudapp.azure.com \
  --username admin \
  --password <your_password> \
  --insecure
```

Then we add the repo:
```
argocd repo add registry-1.docker.io \
  --type helm \
  --name cloudpirates-oci \
  --enable-oci \
```

### Create the OCI app "as YAML code" option using ArgoCD UI:
To avoid Argocd UI bugs, better add the YAML code and create the app. For example for REDIS the yaml code is:
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: redis-oci
  namespace: argocd
spec:
  project: default
  source:
    repoURL: registry-1.docker.io        # <- the registered repo (no oci://, no path)
    chart: cloudpirates/redis            # <- org/repo path inside the registry
    targetRevision: "0.5.0"              # pick a valid Chart version or omit for latest
    helm:
      # optional inline values
      values: |
        auth:
          enabled: true
          password: myRedisPassword
        architecture: standalone
  destination:
    server: https://kubernetes.default.svc
    namespace: redis
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```



## TERRAFORM DESTROY correctly:
- Is better if you delete all your apps using Argocd UI, before Terraform destroy.


- Also in case you use argocd CLI, please Logout first, using:
```
argocd logout argocd.aks-prod.eastus.cloudapp.azure.com
```


- After the previous points are closed, finally destroy your provisionated infrastructure using:
```
terraform destroy -var="install_helmcharts=true"
```



# TO-DO:
- Modularize Terraform project
- Enable using terraform code Prometheus & Grafana option for AKS
- Explore more top ADD-ONs for AKS