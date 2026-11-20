#!/usr/local/bin/ruby

=begin

---- TODO ----
. mettere la versione sulla vpn principale con lo stesso codice qui
. Definire classe Duration con la sua interfaccia di stampa 
  in formato human.
. BUG. se nella stringa di tempo 
. creare una stringa di help che poi si possa copiare nel README
. gestire parametri "--help" e "--verbose" che mostra anche descrizione 
. BUG. Se un utente non compare in /etc/hostname.wg0.users si
  bloccat tutto.

--- DONE ----
. fissare ampiezza delle colonne di output in modo che non ci 
  siano troppi spazi vuoti
. se la stringa di last_handshake_h termina con "." lo tolgo


=end 

# Global is class defined just to have "global variable"
# those global variables are implemented through class methods
class Global
  class << self 
    attr_accessor :peerList, :stanzaList, :user2faList, :opts, :blockedIpList,
                  :justIp, :justUser, :justTime
  end
end

# . estrarre la peer-list
class Peer
  attr_accessor :ip, :mask, :endpoint, :port, :last_handshake, :user, :note
end

class Peer
  # return String representing the time passed since last handshake
  # in a human readable format: "1d.7h.20s" .
  def last_handshake_h()
    oSec = oMin = oHour = oDay = 0 
    oMin, oSec = self.last_handshake.to_i.divmod(60)   
    oHour, oMin = oMin.divmod(60) if oMin >= 60 
    oDay, oHour = oHour.divmod(24) if oHour >= 24
    outStr = ""
    if oDay > 0 then outStr  += "#{oDay}" + "d." end 
    if oHour > 0 then outStr += ("#{oHour}".rjust(2,"0")) + "h." end 
    if oMin > 0 then outStr  += ("#{oMin}".rjust(2,"0")) + "m."  end 
    if oSec > 0 then outStr  += ("#{oSec}".rjust(2,"0")) + "s"  end 
    # . se eventualmente è rimasto un punto alla fine lo tolgo
    outStr.sub! /\.$/, "" 
    outStr    
  end
end

# . variabile globale che controlla se stiamo girando iterattivamente
#   magari con IRB o Pry. Contiene un booleano. 
$inter = !!(defined?(IRB) || defined?(Pry))


# ==================================================
# === Controlli preliminari
# ==================================================
# . questo programma deve girare come "root"
# . se stiamo girando in sessio interattiva (e.g. con Irb) questo
#   controllo è saltato. Dato che si suppone in genere di non voler
#   usare interattivamente Irb come root.
if not $inter
  if `whoami`.strip != "root" then
    STDERR.puts "Error. This you must be root to run this program. Abort."
    exit(1)
  end
end


# ==================================================
# === Creo lista dei Peer attivi
# ==================================================


# . prende lo status dell'interfaccia VP dentro cui ci sono
# --- tipico utente che è stato attivo 
# wgpeer DNocGIpGjjYdlj0ZRI0ogdZTndMZZM6vIuVH5EYXzwg=
#         wgendpoint 93.150.225.63 30295
#         tx: 368508, rx: 340800
#         last handshake: 11833 seconds ago
#         wgaip 10.0.0.11/32
# 
# --- tipico peer che non si è ma il connesso 
# wgpeer b0O883PPJkHMnF918/GSZGZjLY67aS7MW+dMVoPI+gI=
#         tx: 0, rx: 0
#         wgaip 10.0.0.14/32
#
text = if $inter then `doas ifconfig wg0` else  `ifconfig wg0` end


# . prende lista di tutti i peer 
peerTextList = text.split("wgpeer ")

# . dalla lista dei peer tiene solo quello che hanno definita
#   la riga "last handshake"
peerTextList = peerTextList.select { |x| x.include? "last handshake" }

# . ora definisco oggetti Peer che vado meglio
Global.peerList = []
peerTextList.each do |pt|
  p = Peer.new 
  m = pt.match /last handshake: (\d+) seconds/
  sec = m[1]
  p.last_handshake = sec 
  m = pt.match /wgendpoint (\d+\.\d+\.\d+\.\d+) (\d+)/
  p.endpoint = m[1]
  p.port = m[2]
  m = pt.match /wgaip (\d+\.\d+\.\d+\.\d+)\/(\d+)/
  p.ip = m[1]
  p.mask = m[2]  
  Global.peerList.append(p)
end

# ==================================================
# === Decoro lista dei Peer attivi con username e note 
# ==================================================

# . mi serve una descrizione per questi utenti quindi 
#   la vado a prendere per ora dal file /etc/wg0.conf 
text = `cat /etc/hostname.wg0.users`
# . process the file by lines 
lines = text.split /\n/
# . lines starting with # are discarded 
lines = lines.reject { |x| x.match /^\s*#/ }
# . tutte le righe che contengono solo spazi sono scartate
lines = lines.reject { |x| x.match /^\s*$/ }
# . iterates over all lines
# .. a lines to bo valid must have at least 2 fiels separated by | 
#    the IP and the username, optionally a note fiels after the username

lines.each do |l|
  fields = l.split /\|/
  # . if a line has less than 2 fields it is ignored  
  if fields.length < 2 then 
    puts "Warning, line with less than 2 fields: #{l}. Ignored."
    STDERR.puts "Errore di formato. La riga contiene meno dei due field. I field sono separati da '\'. \n#{l}"
    exit(1)
  end
  # . se il primo field non sembra un IP ferma tutto e stampa un messaggio d'errore 
  if not fields[0].strip.match /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ then
    STDERR.puts "Errore il primo field della righa è un ip :\n #{l}"
    exit(1)
  end
  # Se l'ip associato e' tra i Peer attivi allora decoralo con i dati
  # di username e note. Se il field note non esiste viene impostato a nil
  ip = fields[0].strip
  peer = Global.peerList.find { |x| x.ip == ip }
  if peer != nil then
    peer.user = fields[1]
    if fields.length >= 2 then
      peer.note = fields[2]
    else
      peer.note = nil
    end
  end    
end

# ==================================================
# == Stampa dei risultati in output
# ==================================================

# . ordina i Peer in modo che chi ha l'handshake più recente
#   compaia prima nella lista.
Global.peerList.sort! { |a,b| a.last_handshake.to_i <=> b.last_handshake.to_i  } 


# . trovo il massimo numero di caratteri per la colonna IP, user e timeout
Global.justIp = (Global.peerList.map { |x| x.ip.strip.size }).max
Global.justTime = (Global.peerList.map { |x| x.last_handshake_h.strip.size }).max
Global.justUser = (Global.peerList.map { |x| x.user.strip.size }).max
                                                             

Global.peerList.each do |peer|
  ipF = peer.ip.rjust(Global.justIp)
  timeF = peer.last_handshake_h.rjust(Global.justTime)
  userF = peer.user.strip.rjust(Global.justUser)
  noteF = peer.note.strip
  puts "#{ipF}   #{timeF}   #{userF}   #{noteF}"  
  # puts "#{ipF} #{peer.last_handshake}s #{peer.user}"  
end



