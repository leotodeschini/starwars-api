# syntax=docker/dockerfile:1

# Use uma imagem base slim do Python. A versão exata aqui é menos crítica
# pois o mise gerenciará a versão final do Python.
FROM python:3.12-slim as base

# Configurações recomendadas para Python em contêineres
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Instala dependências do sistema: curl e unzip para o mise, git pode ser útil para algumas ferramentas de build.
# Limpa o cache do apt para manter a imagem menor.
RUN apt-get update && apt-get install -y curl unzip git \
    && rm -rf /var/lib/apt/lists/*

# Instala o mise para o usuário root (padrão no Dockerfile até o comando USER)
# O mise será instalado em /root/.local/bin
RUN curl -fsSL https://mise.run | sh
ENV PATH="/root/.local/bin:${PATH}"

# Copia o arquivo .tool-versions para o contêiner.
# Este arquivo diz ao mise qual versão do Python instalar (ex: python 3.12).
COPY .tool-versions .

# Confia no arquivo .tool-versions (boa prática)
# Limpa downloads/instalações potencialmente corrompidas do Python ANTES de tentar instalar.
# A versão 3.12.10 era a que estava falhando no seu log.
# Em seguida, tenta instalar o Python com logs detalhados (MISE_VERBOSE=1).
RUN echo "INFO: Confiando no .tool-versions e limpando caches do mise..." && \
    mise trust .tool-versions || echo "AVISO: Falha ao confiar no .tool-versions, continuando..." && \
    rm -rf /root/.local/share/mise/downloads/python/3.12.10 && \
    rm -rf /root/.local/share/mise/installs/python/3.12.10 && \
    echo "INFO: Tentando instalar Python via mise (conforme .tool-versions)..." && \
    MISE_VERBOSE=1 mise install || \
    (echo "ERRO: Falha na instalação inicial do Python via mise. Tentando fallback para Python 3.12.3..." && \
     # Se a versão do .tool-versions falhar, tenta uma versão patch estável como fallback.
     # Isso ajuda a diagnosticar se o problema é com uma build específica do Python.
     MISE_VERBOSE=1 mise use --global python@3.12.3 && \
     echo "AVISO: Fallback para Python 3.12.3 realizado. Verifique a versão ou corrija a primária.")

# Verifica qual versão do Python o mise está usando agora.
RUN echo "INFO: Versão do Python gerenciada pelo mise:" && mise current python

# Copia o arquivo de dependências do Python.
COPY requirements.txt .

# Instala as dependências do Python.
RUN echo "INFO: Instalando dependências de requirements.txt..." && \
    pip install --no-cache-dir -r requirements.txt

# Cria um usuário não privilegiado para rodar a aplicação (melhor prática de segurança).
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

# Copia o restante do código da sua aplicação.
COPY . .

# Define o proprietário dos arquivos da aplicação para o appuser.
# Isso é importante para que o usuário não privilegiado possa acessar e executar os arquivos.
RUN chown -R appuser:appuser /app

# Muda para o usuário não privilegiado.
USER appuser

# Expõe a porta em que sua aplicação FastAPI (uvicorn) estará rodando.
EXPOSE 8000

# Comando para iniciar sua aplicação.
# Seu main.py já está configurado para rodar na porta 8000.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]