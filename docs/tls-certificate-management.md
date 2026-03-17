# TLS & Certificate Management

## Overview

Azure Front Door Premium provides end-to-end encrypted communication with flexible TLS certificate management options.

---

## TLS Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Minimum TLS Version | 1.2 | Configurable; 1.3 supported |
| HTTPS Redirect | Enabled (301) | All HTTP traffic redirected |
| Origin Protocol | HTTPS Only | TLS between Front Door and origins |
| Supported Ciphers | Azure-managed suite | Strong ciphers only; no legacy CBC |

## Certificate Options

### Option 1: Front Door Managed Certificates

- **Provisioning**: Automatic — Front Door generates and auto-renews certificates
- **Validation**: DNS TXT record or CNAME validation
- **Renewal**: Automatic before expiry
- **Best For**: Standard deployments where Azure manages the full lifecycle

**How it works**:
1. Add a custom domain to Front Door
2. Create a DNS CNAME pointing to the Front Door endpoint
3. Front Door requests a certificate from DigiCert
4. Certificate is issued and deployed to all PoPs within minutes
5. Renewal occurs automatically every 6 months

### Option 2: Customer-Managed Certificates (BYOC)

- **Storage**: Azure Key Vault (in the same subscription)
- **Provisioning**: Customer uploads PFX/PEM to Key Vault
- **Renewal**: Customer responsibility; Front Door detects Key Vault updates
- **Best For**: Organizations requiring specific CAs, EV certificates, or compliance mandates

**How it works**:
1. Upload certificate to Azure Key Vault
2. Grant Front Door managed identity access to Key Vault secrets
3. Reference the Key Vault certificate in Front Door custom domain configuration
4. Front Door automatically picks up renewed certificates from Key Vault

### Comparison

| Aspect | Managed | Customer-Managed (BYOC) |
|--------|---------|------------------------|
| Effort | Zero-touch | Customer handles procurement + upload |
| CA | DigiCert | Any CA |
| EV Support | No | Yes |
| Wildcard | Yes | Yes |
| Auto-Renew | Yes | Via Key Vault auto-rotation |
| Key Vault Required | No | Yes |

## Certificate Rotation Workflow (BYOC)

```
1. Procure new certificate from CA
2. Upload to Azure Key Vault (new version of existing secret)
3. Key Vault notifies Front Door via managed identity
4. Front Door deploys new certificate to all PoPs (< 24 hours typical)
5. Old certificate version can be disabled after confirmation
```

## Multi-Subdomain TLS

Each custom domain (www, api, cdn, portal) can have:
- Its own managed certificate (one per domain)
- A shared wildcard certificate (*.demo.example.com) via BYOC
- SAN certificate covering multiple domains via BYOC

## Origin TLS

- Origins (App Service) use platform-managed certificates (*.azurewebsites.net)
- All origin communication enforced as HTTPS-only
- Certificate name check enabled (enforceCertificateNameCheck: true)
- Minimum TLS 1.2 enforced on origins

## Recommendations for Enterprise Deployment

1. **Start with managed certificates** for rapid onboarding
2. **Migrate to BYOC** if organizational policy requires specific CAs or EV
3. **Use Key Vault auto-rotation** for zero-downtime certificate renewal
4. **Monitor certificate expiry** via Azure Monitor alerts on Key Vault
5. **Maintain wildcard certificates** for simplified multi-subdomain management
