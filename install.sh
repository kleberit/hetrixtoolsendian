#!/bin/bash

# Script de instalação do HetrixTools
echo "=== Instalador HetrixTools ==="

# Aceita SID como parâmetro ou solicita entrada
SID=$1

if [ -z "$SID" ]; then
    echo -n "Digite o SID: "
    read SID
fi

# Valida se o SID foi informado
if [ -z "$SID" ]; then
    echo "Erro: SID não pode estar vazio!"
    exit 1
fi

echo "SID: $SID"

# Verifica se está sendo executado dentro do diretório correto
if [ ! -f "hetrixtools.cfg" ] || [ ! -f "hetrixtools_agent.sh" ]; then
    echo "Erro: Execute este script dentro do diretório hetrixtoolsendian clonado!"
    exit 1
fi

echo "Iniciando instalação..."

# Copia a pasta atual para /usr/local/hetrixtools
echo "Copiando arquivos para /usr/local/hetrixtools..."
sudo cp -r . /usr/local/hetrixtools

# Remove arquivos git da cópia
sudo rm -rf /usr/local/hetrixtools/.git
sudo rm -rf /usr/local/hetrixtools/.gitignore

# Insere o SID no arquivo de configuração
echo "Configurando SID..."
sudo sed -i "s/SID=\"\"/SID=\"$SID\"/" /usr/local/hetrixtools/hetrixtools.cfg

# Dá permissão de execução ao script do agent
echo "Definindo permissões..."
sudo chmod +x /usr/local/hetrixtools/hetrixtools_agent.sh

# Adiciona a linha no crontab
echo "Configurando cron..."
echo "* * * * * /usr/local/hetrixtools/hetrixtools_agent.sh >/dev/null 2>&1" | sudo tee -a /etc/crontab

# Reinicia o serviço fcron
echo "Reiniciando fcron..."
sudo /etc/init.d/fcron restart

echo "=== Instalação concluída com sucesso! ==="
echo "SID configurado: $SID"
echo "O agente HetrixTools está agora em execução."
