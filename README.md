# Proxy Systemctl for Docker

O **Proxy Systemctl** é uma solução avançada para ambientes Docker onde o `systemd` está ausente. Ele atua como um intermediário inteligente (proxy) que intercepta chamadas ao comando `systemctl`, traduz as definições de serviços nativas do Linux (`.service`) e as gerencia automaticamente via **Supervisor**.

---

## 🔑 Logic

A lógica desta ferramenta é a **Sincronização por Tradução de Metadados**. O Proxy localiza o arquivo de unidade original (`.service`), realiza o *parsing* de diretivas como `ExecStart`, `User`, `Group` e `EnvironmentFile`, e gera um espelho de configuração fiel para o Supervisor.

---

## 🚀 Funcionalidades

* **Intermediação Inteligente:** Intercepta `enable`, `start`, `stop` e `disable`.
* **Autodiscovery (Varredura Ativa):** Identifica e integra serviços pré-instalados automaticamente.
* **Marcação Transparente:** Edições envelopadas por `### [SYSTEMCTL-PROXY-START] ###`.
* **Dashboard CLI:** Comando para listar serviços capturados e seus status.
* **Rollback Seguro:** Desinstalação completa via parâmetro `--delete`.

---

## 🛠 Modo de Utilização

### Instalação no Dockerfile

Para garantir o funcionamento, você deve seguir dois passos no seu `Dockerfile`:

1. **Instalação do Proxy:** Execute o script de automação.
2. **Inicialização do Daemon:** O Supervisor **DEVE** ser o último comando para manter o container vivo.

```dockerfile
# 1. Instalação (Pode ser em qualquer parte do build)
RUN curl -sSL [https://raw.githubusercontent.com/seu-usuario/proxy-systemctl/main/install.sh](https://raw.githubusercontent.com/seu-usuario/proxy-systemctl/main/install.sh) -o install.sh \
    && chmod +x install.sh \
    && ./install.sh

# 2. Inicialização (OBRIGATORIAMENTE a última linha do Dockerfile)
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
```

<a href="https://github.com/tiagomf1/docker-systemd-proxy/blob/master/UAP/UAP_Philosophy.md">
  <img src="https://github.com/tiagomf1/docker-systemd-proxy/blob/master/UAP/uap_p.png?raw=true" width="200" alt="UAP Level Badge"> 80%
</a>
