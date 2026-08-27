# Rotação manual de segredos

Este procedimento deve ser executado somente depois de implantar as referências
por variáveis de ambiente. Não coloque valores reais em commits, tickets, logs ou
mensagens.

## Ordem recomendada

1. Faça backup privado dos arquivos `.env` e dos tokens atuais.
2. Gere uma credencial nova no provedor.
3. Atualize somente o `.env` local ou o cofre de segredos do servidor.
4. Recrie o container sem usar `--build-arg` para segredos.
5. Teste a integração e confira se logs e respostas não exibem credenciais.
6. Revogue a credencial antiga.
7. Limpe o histórico Git em clones espelho, seguindo o plano abaixo.
8. Force o reenvio coordenado e peça que todos façam clone novo.
9. Recrie imagens com `docker compose build --no-cache` e remova imagens antigas
   somente depois de validar a nova versão.
10. Revise backups e registros de container; credenciais revogadas podem continuar
    presentes neles e devem seguir uma política de retenção segura.

## Google Calendar e Google Contacts

Links:

- Credenciais: https://console.cloud.google.com/apis/credentials
- Rotação oficial: https://support.google.com/cloud/answer/15549257
- Conexões e consentimentos da conta: https://myaccount.google.com/connections
- Revogação OAuth: https://developers.google.com/identity/protocols/oauth2/web-server#tokenrevoke

Checklist:

- Selecione o projeto correto e abra o cliente OAuth usado pela aplicação.
- Adicione um novo client secret e mantenha o antigo ativo somente durante a troca.
- Atualize `GOOGLE_CALENDAR_CLIENT_ID`, `GOOGLE_CALENDAR_CLIENT_SECRET` e
  `GOOGLE_CALENDAR_REDIRECT_URI`.
- Atualize `GOOGLE_CONTACTS_CLIENT_ID`, `GOOGLE_CONTACTS_CLIENT_SECRET` e
  `GOOGLE_CONTACTS_REDIRECT_URI`.
- Gere novos consentimentos/tokens quando necessário e salve-os apenas em
  `secure-data/` ou no cofre de segredos.
- Configure caminhos absolutos em `GOOGLE_CALENDAR_TOKEN_PATH` e
  `GOOGLE_CONTACTS_TOKEN_PATH`.
- Teste Calendar e Contacts; depois desative e exclua o secret antigo.
- Revogue tokens antigos e consentimentos comprometidos.
- Depois da rotação, remova as cópias `legacy-credentials.json` preservadas em
  `secure-data/`.
- No servidor, deixe `secure-data/` acessível somente ao usuário/grupo do Apache
  e restrinja os tokens para leitura e escrita desse usuário. Confirme o UID/GID
  do container antes de aplicar `chown` ou `chmod`, para não interromper o OAuth.

## Wonca

Links:

- Site e contato oficial: https://www.wonca.com.br/

Não foi localizada uma página pública e verificável de autogestão das chaves.
Use o painel contratado ou o contato oficial para revogar e gerar duas chaves
distintas. Atualize `WONCA_API_KEY_TRACK` e `WONCA_API_KEY_TRACK_CODE`, teste os
dois endpoints e só então revogue as chaves anteriores.

## APIBrasil e API Grátis

Links:

- Painel: https://apibrasil.com.br/
- Documentação: https://doc.apibrasil.io/
- SDK e fluxo de devices: https://github.com/APIBrasil/apigratis-sdk-node

Checklist:

- Invalide os devices expostos e crie devices novos no painel.
- Renove a sessão/credencial que emite o Bearer Token.
- Atualize `APIBRASIL_DEVICE_TOKEN` e `APIBRASIL_BEARER_TOKEN`.
- Para a integração legada, atualize `APIGRATIS_DEVICE_TOKEN` e
  `APIGRATIS_BEARER_TOKEN`.
- Teste pelo backend. Nunca envie esses valores ao JavaScript do navegador.

## Banco de dados

- Crie um usuário exclusivo para cada aplicação, com privilégio mínimo.
- Altere a senha no MariaDB antes de substituir `DB_USER` e `DB_PASS`.
- Atualize `MARIADB_ROOT_PASSWORD` em `infra/.env` somente quando houver uma
  janela coordenada para rotacionar a conta administrativa.
- Lembre que trocar o valor no Compose não altera a senha de um volume MariaDB
  já inicializado.
- Recrie os containers e confirme a conexão antes de revogar usuários antigos.

## Senha temporária de manutenção

- Gere um valor longo e aleatório para `API_MAINTENANCE_PASS`.
- Distribua-o apenas por um cofre de segredos.
- Trate essa senha como transição. Substitua o parâmetro `pass` por autenticação
  de usuário ou serviço, autorização por rota, expiração e auditoria.

## Plano de limpeza do histórico Git

Não execute os comandos abaixo no diretório de trabalho atual. Faça clone espelho,
teste a reescrita e combine a janela com todos os colaboradores.

Ferramenta e documentação:
https://github.com/newren/git-filter-repo/blob/main/Documentation/git-filter-repo.txt

Arquivos detectados no histórico:

- `php/googlecalendar`: `credentials.json`, `sftp-config.json`, `config.php`,
  `configLocalhost.php`, `configLocalhost_Servidor.php`, `configServidor.php` e
  `config_example.php`.
- `php/peoplecontacts`: `credentials.json`, `sftp-config.json`, `config.php`,
  `index.php`, `configLocalhost.php`, `configServidor.php` e
  `config_example.php`.
- `node/apigsfacil`: `sftp-config.json`,
  `src/controllers/AutomaticController.js` e `src/middleware/Auth.js`.
- Nenhum caminho `secure-data/` ou `token*.json` foi encontrado nos objetos Git
  examinados.

Para os segredos que apareceram em arquivos de código mantidos, crie fora do
repositório um arquivo `replacements.txt`, com permissão `0600`, contendo cada
valor antigo exato no formato aceito por `git filter-repo --replace-text`. Esse
arquivo é sensível: não o versione, não o compartilhe e destrua-o depois da
validação.

Para cada repositório, faça uma única reescrita combinando a remoção dos arquivos
e a substituição nos arquivos de código:

```bash
git clone --mirror URL_DO_REPOSITORIO repo-clean.git
cd repo-clean.git
chmod 600 /caminho/privado/replacements.txt
git filter-repo --sensitive-data-removal \
  --replace-text /caminho/privado/replacements.txt \
  --invert-paths \
  --path credentials.json \
  --path sftp-config.json \
  --path configLocalhost.php \
  --path configLocalhost_Servidor.php \
  --path configServidor.php \
  --path config_example.php
git fsck --full
```

Remova dos argumentos os caminhos que não existirem naquele repositório. Não
remova `config.php`, `index.php`, `AutomaticController.js` ou `Auth.js`, pois são
arquivos de código ainda necessários.

Valide em outro clone antes de publicar. Somente após a rotação de todos os
segredos e a aprovação da equipe:

```bash
git push --force --mirror
```

O repositório `node/apigsfacil` é submódulo da raiz. Depois da reescrita dele,
será necessário apontar o repositório raiz para o novo commit do submódulo. Os
projetos PHP têm repositórios próprios e devem ser limpos separadamente.
