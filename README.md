# CCTV Motorista — Android e iOS

Aplicação Flutter para turnos, horas, vencimentos, relatórios PDF/Excel e backups.
Android e iOS partilham os mesmos ecrãs e cálculos. O Android mantém o Google
Drive e a distribuição existente por APK. O iPhone/iPad usa iCloud para backups.

## Sem Mac nem iPhone

O código pode ser desenvolvido neste computador Windows. O workflow Build Flutter
iOS em .github/workflows/build_ios.yml compila num Mac remoto do GitHub Actions.
Para o utilizar, enviar estas alterações ao GitHub e abrir Actions > Build Flutter
iOS > Run workflow. Também é executado com tags v*. Verificar as condições e
minutos disponíveis na conta GitHub antes de executar.

O resultado cctv-motorista-ios-unsigned contém Runner.app sem assinatura.
Serve para verificar a compilação; não é um IPA instalável e não publica nada.
Este workflow ainda não foi executado a partir deste computador.

O mesmo workflow gera cctv-motorista-ios-simulator, com um ZIP para um iPhone
virtual. Descarregar o artefacto no GitHub, extrair o ZIP exterior do artefacto e
enviar o ficheiro cctv-motorista-simulator.zip ao Appetize (https://appetize.io).
Esse serviço permite utilizar a app no navegador Windows. A versão de simulador
é diferente da versão para dispositivo e não precisa de assinatura de distribuição.
Consultar os planos do serviço. Testar os ecrãs e os cálculos; validar o iCloud
separadamente num ambiente Apple com conta iCloud e direitos configurados.

Para instalar e distribuir, será necessária uma conta Apple Developer, um
identificador da aplicação e certificados/perfis de assinatura. A conta pode
ser gerida pelo navegador. O programa Apple Developer custa 99 USD por ano ou
valor local aplicável: https://developer.apple.com/programs/

Após a inscrição, configurar a assinatura numa máquina Mac remota ou emprestada,
gerar o IPA e enviar ao App Store Connect. Alguém com um iPhone pode testar pelo
TestFlight. Não é necessário comprar um Mac, mas os testes finais do iCloud e Face
ID precisam de um dispositivo Apple com uma conta iCloud ativa.

## Configurar iCloud e assinatura Apple

Identificador da aplicação: com.ruibarata.cctvmotorista. Versão mínima: iOS 15.
Contentor iCloud: iCloud.com.ruibarata.cctvmotorista.

Na conta Apple Developer, registar o identificador, ativar iCloud e associar o
contentor indicado. O perfil de assinatura tem de incluir esses direitos.
Num Mac com Flutter 3.47.2, Xcode com suporte iOS e CocoaPods:

```sh
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

No Xcode, selecionar Runner, configurar a equipa Apple em Signing & Capabilities,
e confirmar iCloud > iCloud Documents e o contentor. O projeto inclui os direitos
em ios/Runner/Runner.entitlements. A integração usa as APIs nativas Apple e não
precisa de credenciais Google na versão iOS.

```sh
flutter build ipa --release
```

Enviar pelo Xcode Organizer para App Store Connect e disponibilizar no TestFlight
ou submeter à App Store. Preencher a ficha e os dados de privacidade na submissão.
As atualizações iOS são distribuídas pela App Store/TestFlight, sem instalar APKs.

## Utilizar o backup iCloud

No iPhone, iniciar sessão na conta Apple e ativar iCloud Drive nas Definições.
Na aplicação abrir iCloud (Cópia de Segurança):

- Guardar no iCloud: guarda os registos e as definições gerais e mensais.
- Recuperar do iCloud: pede confirmação; substitui os dias coincidentes e as
  definições pelos da cópia, mantendo os restantes dias locais.

As cópias iCloud são manuais. Guardar novamente depois de alterar os registos.
O iOS gere o envio conforme a ligação; uma cópia guardada localmente na pasta
iCloud pode ainda estar a aguardar envio. Se o restauro iniciar um download,
aguardar e voltar a tocar em Recuperar. O PIN e as credenciais não são incluídos.
A cópia é substituída a cada gravação. Não há sincronização entre iCloud e Google Drive.

## Verificação

Executar flutter analyze e flutter test. Antes de distribuir, testar num iPhone
e iPad: turnos, persistência, Face ID/PIN, PDF/Excel, guardar em Ficheiros,
partilha e backup/restauro iCloud, incluindo ausência de rede e troca de conta.
A compilação Xcode e a integração iCloud não foram verificadas no Windows.

## Backups visíveis através de Ficheiros

Na versão iOS de teste, o caminho recomendado é Guardar em Ficheiros. No seletor
nativo, escolher iCloud Drive, uma pasta e Guardar. A aplicação exporta um JSON
com registos e definições gerais/mensais, sem o PIN ou credenciais. O iOS confirma
a exportação para o destino escolhido; o envio remoto é gerido pelo fornecedor
Ficheiros. A aplicação não apresenta essa exportação como prova de envio ao servidor.

Para recuperar, utilizar Recuperar de Ficheiros e selecionar o JSON guardado.
O restauro pede confirmação antes de substituir registos coincidentes e definições.
Os nomes de exportação incluem a data/hora para manter cópias diferentes.

O acesso à pasta própria da aplicação fica numa secção adicional e depende da
configuração do contentor Apple. A ausência de acesso a esse contentor não impede
exportar para um destino disponibilizado pelo seletor Ficheiros do iOS.
