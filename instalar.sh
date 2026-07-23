#!/bin/bash
set -e

echo "================================================================="
echo "   INSTALADOR MESTRE: ARCH LINUX DO CARLOS (DEFINITIVO v14)     "
echo "================================================================="

# PASSO 0.0: Exigir boot em modo UEFI
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "❌ ERRO: o sistema não bootou em modo UEFI. Reinicie o pendrive em modo UEFI."
    exit 1
fi

# PASSO 0.1: Verificar Conexão com a Internet
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "❌ ERRO: Sem conexão com a internet! Conecte-se ao Wi-Fi/cabo antes de rodar."
    exit 1
fi

# PASSO 0.2: Definição de Usuário e Senha Segura
USUARIO="carlos"
echo "[0/9] Configuração de credenciais:"
read -s -p "Digite a senha para o usuário '$USUARIO' e para o ROOT: " SENHA
echo
read -s -p "Confirme a senha: " SENHA_CONFIRM
echo
if [ "$SENHA" != "$SENHA_CONFIRM" ] || [ -z "$SENHA" ]; then
    echo "❌ Erro: As senhas não coincidem ou estão em branco. Abortando."
    exit 1
fi

# PASSO 0.3: Identificar e Confirmar o Disco
echo "-----------------------------------------------------------------"
lsblk
echo "-----------------------------------------------------------------"
read -p "Digite o nome exato do SSD/HD para INSTALAR (ex: /dev/sda ou /dev/nvme0n1): " DISCO

if [ ! -b "$DISCO" ]; then
    echo "❌ Erro: '$DISCO' não é um dispositivo de bloco válido. Abortando."
    exit 1
fi

echo "⚠️ ATENÇÃO: TODOS OS DADOS EM $DISCO SERÃO APAGADOS PERMANENTEMENTE!"
read -p "Para confirmar, digite novamente o caminho exato do disco ($DISCO): " CONFIRM_DISCO
if [ "$CONFIRM_DISCO" != "$DISCO" ]; then
    echo "❌ Instalação cancelada por incompatibilidade na confirmação."
    exit 1
fi

# PASSO 0.4: Buscar os mirrors mais rápidos com verificação de segurança
echo "[0.4/9] Otimizando lista de mirrors (Brasil)..."
if command -v reflector >/dev/null 2>&1; then
    reflector --country Brazil --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null \
        || echo "⚠️ Reflector falhou, seguindo com os mirrors padrão."
else
    echo "⚠️ Reflector não encontrado na ISO, seguindo com os mirrors padrão."
fi

# PASSO 0.5: Habilitar multilib/paralelismo/cor no pacman da ISO viva
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include/s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# PASSO 1: Limpeza prévia robusta (sgdisk + wipefs), particionamento e udevadm settle
echo "[1/9] Limpando partições antigas (sgdisk/wipefs) e formatando $DISCO..."
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

sgdisk --zap-all "$DISCO"
wipefs -a "$DISCO"
parted -s "$DISCO" mklabel gpt
parted -s "$DISCO" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISCO" set 1 esp on
parted -s "$DISCO" mkpart primary ext4 513MiB 100%

if [[ "$DISCO" == *"nvme"* ]]; then
    PART_EFI="${DISCO}p1"
    PARTICAO="${DISCO}p2"
else
    PART_EFI="${DISCO}1"
    PARTICAO="${DISCO}2"
fi

udevadm settle
partprobe "$DISCO"
sleep 2

if [ ! -b "$PART_EFI" ] || [ ! -b "$PARTICAO" ]; then
    echo "❌ ERRO: Falha ao criar as partições EFI ou Raiz. Abortando."
    exit 1
fi

mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 -F "$PARTICAO"

mount "$PARTICAO" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot
echo "✅ Partições montadas: /mnt (raiz) e /mnt/boot (EFI)"

# PASSO 2: Instalando a Base (Intel otimizado + Kitty de terminal alternativo)
echo "[2/9] Baixando e instalando o Kernel, Drivers e Programas..."
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers intel-ucode \
    sof-firmware linux-firmware-marvell \
    networkmanager network-manager-applet grub efibootmgr sudo git ntfs-3g \
    sway waybar wofi swaylock swayidle swaybg foot kitty thunar \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    polkit polkit-gnome xdg-desktop-portal xdg-desktop-portal-wlr xdg-user-dirs \
    grim slurp wl-clipboard brightnessctl btop htop zenity trash-cli galculator inotify-tools \
    flatpak blueman bluez ufw tlp zram-generator pacman-contrib \
    mesa vulkan-intel intel-media-driver lib32-mesa lib32-vulkan-intel \
    steam gamemode lib32-gamemode mangohud gamescope xorg-xwayland \
    cliphist mako libnotify upower openssl \
    fastfetch curl wget unzip zip p7zip rsync tree less \
    dosfstools mtools e2fsprogs bash-completion ripgrep fd fzf bat eza \
    ttf-dejavu noto-fonts noto-fonts-emoji nano man-db man-pages

# PASSO 3: Gerando o Mapa de Discos (FSTAB)
echo "[3/9] Gerando arquivo /etc/fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# PASSO 4: Configuração do Sistema via Arch-Chroot
echo "[4/9] Configurando Idioma, Relógio, Bootloader, Usuário e Otimizações..."
arch-chroot /mnt /bin/bash <<EOF
# Fuso horário e relógio
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd

# Idioma e Teclado
echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Nome do computador + /etc/hosts
echo "carlos-pc" > /etc/hostname
cat > /etc/hosts << 'HOSTS_EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   carlos-pc.localdomain carlos-pc
HOSTS_EOF

# Pacman: otimizações no sistema final
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include/s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# Bootloader GRUB (UEFI) com verificação completa
if ! grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB; then
    echo "❌ ERRO CRÍTICO: Falha ao executar grub-install!"
    exit 1
fi

if ! grub-mkconfig -o /boot/grub/grub.cfg; then
    echo "❌ ERRO CRÍTICO: Falha ao gerar o grub.cfg!"
    exit 1
fi

# Criar Usuário e Senhas com Hash seguro
useradd -m -G wheel,video,input,audio,storage,render -s /bin/bash $USUARIO
HASH_SENHA=\$(openssl passwd -6 "$SENHA")
echo "$USUARIO:\$HASH_SENHA" | chpasswd -e
echo "root:\$HASH_SENHA" | chpasswd -e

# Sudo seguro via sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

# zram config
cat > /etc/systemd/zram-generator.conf << 'ZRAM_EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
ZRAM_EOF
echo "vm.swappiness=180" > /etc/sysctl.d/99-zram.conf

# journald limite de tamanho
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf << 'JOURNAL_EOF'
[Journal]
SystemMaxUse=200M
JOURNAL_EOF

# makepkg com todos os núcleos
sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j\$(nproc)"/' /etc/makepkg.conf

# xdg-user-dirs em português
mkdir -p /home/$USUARIO/.config
cat > /home/$USUARIO/.config/user-dirs.dirs << 'DIRS_EOF'
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documentos"
XDG_MUSIC_DIR="$HOME/Músicas"
XDG_PICTURES_DIR="$HOME/Imagens"
XDG_VIDEOS_DIR="$HOME/Vídeos"
DIRS_EOF
echo "enabled=False" > /home/$USUARIO/.config/user-dirs.conf

# Flathub remote (--system)
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Serviço de primeiro boot para Flatpak (desativação apenas em caso de sucesso real)
cat > /etc/systemd/system/primeiro-boot-flatpak.service << 'FLATPAK_EOF'
[Unit]
Description=Instala apps Flatpak no primeiro boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/flatpak/.primeiro-boot-feito

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
    for i in {1..5}; do \
        if /usr/bin/flatpak install --system -y flathub org.mozilla.firefox org.onlyoffice.desktopeditors; then \
            touch /var/lib/flatpak/.primeiro-boot-feito; \
            /usr/bin/systemctl disable primeiro-boot-flatpak.service; \
            exit 0; \
        fi; \
        sleep 30; \
    done; exit 1'

[Install]
WantedBy=multi-user.target
FLATPAK_EOF

# DNS moderno com systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Ativar serviços do sistema
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable fstrim.timer
systemctl enable tlp
systemctl enable ufw
systemctl enable upower.service
systemctl enable systemd-resolved
systemctl enable paccache.timer
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
systemctl enable primeiro-boot-flatpak.service
EOF

# PASSO 5: Criando Estrutura de Pastas do Usuário com antecedência correta
echo "[5/9] Criando diretórios pessoais e arquivos de configuração iniciais..."
mkdir -p /mnt/home/$USUARIO/{Downloads,Documentos,Músicas,Jogos,Aplicativos,Compactados}
mkdir -p /mnt/home/$USUARIO/Imagens/{prints,wallpapers}
mkdir -p /mnt/home/$USUARIO/Vídeos/{clipes,animados}
mkdir -p /mnt/home/$USUARIO/.config/sway
mkdir -p /mnt/home/$USUARIO/.config/sway/scripts
mkdir -p /mnt/home/$USUARIO/.config/systemd/user

# Script de fundo sólido limpo
cat << 'EOF' > /mnt/home/$USUARIO/.config/sway/wallpaper-atual.sh
#!/bin/bash
swaybg -c '#1a1b26' &
EOF
chmod +x /mnt/home/$USUARIO/.config/sway/wallpaper-atual.sh

# PASSO 6: Sway abrindo sozinho no login do TTY1
echo "[6/9] Configurando auto-início do Sway no TTY1..."
cat << 'EOF' >> /mnt/home/$USUARIO/.bash_profile
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec sway
fi
EOF

# PASSO 7: Scripts Utilitários e Organizador como Systemd User Service
echo "[7/9] Configurando a interface Sway, atalhos e serviço de organização..."

# Organizador de Downloads (Script Executável)
cat << 'EOF' > /mnt/home/$USUARIO/.organizar-downloads.sh
#!/bin/bash
mkdir -p ~/Downloads ~/Músicas ~/Documentos ~/Aplicativos ~/Vídeos/animados ~/Imagens ~/Vídeos ~/Compactados
inotifywait -m -e create -e moved_to --format '%f' ~/Downloads | while read -r ARQUIVO; do
    origem=~/Downloads/"$ARQUIVO"
    [ -f "$origem" ] || continue
    case "$ARQUIVO" in
        *.mp3|*.MP3|*.flac|*.WAV|*.wav) mv -n "$origem" ~/Músicas/ 2>/dev/null ;;
        *.pdf|*.PDF|*.txt|*.docx|*.xlsx|*.pptx|*.doc) mv -n "$origem" ~/Documentos/ 2>/dev/null ;;
        *.exe|*.AppImage|*.apk) mv -n "$origem" ~/Aplicativos/ 2>/dev/null ;;
        *.zip|*.rar|*.7z|*.tar.gz|*.tgz|*.tar.xz) mv -n "$origem" ~/Compactados/ 2>/dev/null ;;
        *.iso) mv -n "$origem" ~/Downloads/ 2>/dev/null ;;
        *.gif) mv -n "$origem" ~/Vídeos/animados/ 2>/dev/null ;;
        *.png|*.jpeg|*.jpg) mv -n "$origem" ~/Imagens/ 2>/dev/null ;;
        *.mp4|*.mkv|*.webm) mv -n "$origem" ~/Vídeos/ 2>/dev/null ;;
    esac
done
EOF
chmod +x /mnt/home/$USUARIO/.organizar-downloads.sh

# Serviço Systemd User para o Organizador de Downloads (garantindo start após o ambiente gráfico)
cat << 'EOF' > /mnt/home/$USUARIO/.config/systemd/user/organizar-downloads.service
[Unit]
Description=Organizador automático de downloads via inotify
After=sway-session.target graphical-session.target

[Service]
ExecStart=%h/.organizar-downloads.sh
Restart=always
RestartSec=5

[Install]
WantedBy=sway-session.target graphical-session.target
EOF

# Menu de Energia
cat << 'EOF' > /mnt/home/$USUARIO/.config/sway/menu-energia.sh
#!/bin/bash
escolha=$(printf "🔒 Bloquear Tela\n🔄 Reiniciar\n🔌 Desligar\n🚪 Sair do Sway\n❌ Cancelar" | wofi --dmenu --prompt="Sistema")
case "$escolha" in
    "🔒 Bloquear Tela") swaylock -c 1a1b26 ;;
    "🔄 Reiniciar") systemctl reboot ;;
    "🔌 Desligar") systemctl poweroff ;;
    "🚪 Sair do Sway") swaymsg exit ;;
esac
EOF
chmod +x /mnt/home/$USUARIO/.config/sway/menu-energia.sh

# Seletor de Wallpaper
cat << 'EOF' > /mnt/home/$USUARIO/.config/sway/trocar-wallpaper.sh
#!/bin/bash
DIRETORIO_WALLPAPERS="$HOME/Imagens/wallpapers"

if [ ! -d "$DIRETORIO_WALLPAPERS" ] || [ -z "$(ls -A "$DIRETORIO_WALLPAPERS")" ]; then
    notify-send "⚠️ Aviso" "A pasta ~/Imagens/wallpapers está vazia!"
    exit 1
fi

escolha=$(ls -1 "$DIRETORIO_WALLPAPERS" | wofi --dmenu --prompt="Wallpaper")
if [ -n "$escolha" ]; then
    IMAGEM="$DIRETORIO_WALLPAPERS/$escolha"
    pkill swaybg || true
    swaybg -i "$IMAGEM" -m fill &
    echo "swaybg -i '$IMAGEM' -m fill &" > "$HOME/.config/sway/wallpaper-atual.sh"
    chmod +x "$HOME/.config/sway/wallpaper-atual.sh"
    notify-send "🎨 Wallpaper Alterado" "Novo fundo aplicado!"
fi
EOF
chmod +x /mnt/home/$USUARIO/.config/sway/trocar-wallpaper.sh

# Lixeira Segura
cat << 'EOF' > /mnt/home/$USUARIO/.config/sway/scripts/lixeira-segura.sh
#!/bin/bash
arquivo="$1"
if [ -z "$arquivo" ]; then exit 0; fi
zenity --question --text="Tem certeza que deseja enviar este arquivo para a lixeira?\n\n$(basename "$arquivo")" --title="Confirmação de Exclusão"
if [ $? -eq 0 ]; then trash-put "$arquivo"; fi
EOF
chmod +x /mnt/home/$USUARIO/.config/sway/scripts/lixeira-segura.sh

# Arquivo de Configuração Principal do Sway
cat << 'EOF' > /mnt/home/$USUARIO/.config/sway/config
set $mod Mod4

input * {
    xkb_layout "br"
    xkb_variant "abnt2"
}

input "type:touchpad" {
    tap enabled
    natural_scroll enabled
}

floating_modifier $mod normal

output * bg #1a1b26 solid_color

# Estilo
default_border pixel 2
gaps inner 6
gaps outer 2
client.focused #7aa2f7 #1a1b26 #c0caf5 #7aa2f7 #7aa2f7

# Apps e atalhos
bindsym $mod+d exec wofi --show drun --prompt="Apps"
bindsym $mod+Return exec foot
bindsym $mod+Shift+Return exec kitty
bindsym $mod+Shift+q kill
bindsym $mod+l exec swaylock -c 1a1b26
bindsym $mod+x exec ~/.config/sway/menu-energia.sh
bindsym $mod+w exec ~/.config/sway/trocar-wallpaper.sh
bindsym $mod+n exec foot -e nano ~/Documentos/rascunho.txt
bindsym $mod+e exec thunar
bindsym $mod+c exec galculator
bindsym $mod+Shift+c reload
bindsym Control+Shift+Escape exec foot -e btop
bindsym $mod+v exec sh -c 'cliphist list | wofi --dmenu --prompt="Clipboard" | cliphist decode | wl-copy'
bindsym Print exec grim ~/Imagens/prints/print-$(date +'%Y-%m-%d_%H-%M-%S').png
bindsym Shift+Print exec grim -g "$(slurp)" ~/Imagens/prints/print-recorte-$(date +'%Y-%m-%d_%H-%M-%S').png

# Navegação entre janelas e workspaces
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5

# Volume e brilho
bindsym XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym XF86MonBrightnessUp exec brightnessctl set +5%
bindsym XF86MonBrightnessDown exec brightnessctl set 5%-

# Inicialização
exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec nm-applet --indicator
exec blueman-applet
exec wl-paste --type text --watch cliphist store
exec mako
exec swayidle -w \
    timeout 300 'swaylock -c 1a1b26' \
    timeout 600 'swaymsg "output * dpms off"' \
    resume 'swaymsg "output * dpms on"'
exec_always sh -c '[ -f ~/.config/sway/wallpaper-atual.sh ] && ~/.config/sway/wallpaper-atual.sh'
exec_always sh -c 'pkill -x waybar; waybar'
EOF

# PASSO 8: Configuração da Waybar
echo "[8/9] Configurando a Waybar (Painel Superior)..."
mkdir -p /mnt/home/$USUARIO/.config/waybar

cat << 'EOF' > /mnt/home/$USUARIO/.config/waybar/config
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["sway/workspaces", "custom/firefox", "custom/steam", "custom/office", "custom/calc", "custom/files"],
    "modules-center": ["clock"],
    "modules-right": ["battery", "network", "bluetooth", "cpu", "memory", "tray"],

    "sway/workspaces": {
        "disable-scroll": false
    },
    "tray": {
        "spacing": 10
    },
    "custom/firefox": { "format": "🌐 Firefox", "on-click": "flatpak run org.mozilla.firefox" },
    "custom/steam": { "format": "🎮 Steam", "on-click": "steam" },
    "custom/office": { "format": "📊 Office", "on-click": "flatpak run org.onlyoffice.desktopeditors" },
    "custom/calc": { "format": "🧮 Calc", "on-click": "galculator" },
    "custom/files": { "format": "📁 Computador", "on-click": "thunar" },
    "battery": {
        "format": "{capacity}% 🔋",
        "format-charging": "{capacity}% ⚡",
        "format-plugged": "{capacity}% 🔌",
        "states": { "warning": 30, "critical": 15 },
        "interval": 10
    },
    "network": { "format-wifi": "🛜 {essid}", "format-disconnected": "⚠️ Sem Rede", "on-click": "foot -e nmtui", "interval": 5 },
    "bluetooth": { "format": " {status}", "format-connected": " {device_alias}", "on-click": "blueman-manager", "interval": 5 },
    "cpu": { "format": "💻 CPU: {usage}%", "interval": 5 },
    "memory": { "format": "RAM: {percentage}%", "interval": 5 },
    "clock": { "format": "{:%d/%m/%Y - %H:%M}", "interval": 60 }
}
EOF

cat << 'EOF' > /mnt/home/$USUARIO/.config/waybar/style.css
* { font-family: monospace; font-size: 13px; }
window#waybar { background: #1a1b26; color: #c0caf5; }
#battery { padding: 0 10px; color: #9ece6a; }
#battery.warning { color: #e0af68; }
#battery.critical { color: #f7768e; animation: blink 1s steps(1, start) infinite; }
@keyframes blink { to { background-color: #f7768e; color: #1a1b26; } }
EOF

# PASSO 9: Permissões Finais, Correção de Linger (loginctl correto) e Habilitação Segura do Serviço User
echo "[9/9] Ajustando permissões finais, ativando linger e registrando serviço de usuário..."
arch-chroot /mnt chown -R $USUARIO:$USUARIO /home/$USUARIO

# Correção aplicada: loginctl (sem o 'n' no final)
arch-chroot /mnt loginctl enable-linger $USUARIO 2>/dev/null || true

# Criação do link simbólico direto no disco montado para ativar o serviço de usuário no target do Sway
mkdir -p /mnt/home/$USUARIO/.config/systemd/user/sway-session.target.wants
ln -sf /home/$USUARIO/.config/systemd/user/organizar-downloads.service /mnt/home/$USUARIO/.config/systemd/user/sway-session.target.wants/organizar-downloads.service 2>/dev/null || true
arch-chroot /mnt chown -R $USUARIO:$USUARIO /home/$USUARIO/.config/systemd

echo "================================================================="
echo "   INSTALAÇÃO CONCLUÍDA COM SUCESSO (v14 DEFINITIVA)!          "
echo "================================================================="
echo ""
echo "   Correções aplicadas nesta versão:"
echo "   - Corrigido o erro de digitação de 'loginctln' para 'loginctl'."
echo "   - Mantido o ecossistema ideal e focado para hardware Intel (i3-1115G4)."
echo ""
echo "   Para finalizar:"
echo "   1. Digite: umount -R /mnt                                      "
echo "   2. Digite: reboot                                              "
echo "   3. Retire o pendrive!                                          "
echo "================================================================="