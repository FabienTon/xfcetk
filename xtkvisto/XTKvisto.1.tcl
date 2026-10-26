#!/usr/bin/env wish

#---------------------------------------------
# XTKvisto
# visionneuse d'images
# Daniel Macouin fevrier 2026
# logiciel libre de droits 
# sans garanties
#---------------------------------------------

package require Tk
package require Img
package require msgcat

# =============================================================================
# === Internationalisation =====================================================
# =============================================================================

# Résoudre le répertoire du script de façon robuste
if {[info script] ne ""} {
	set ::script_dir [file dirname [file normalize [info script]]]
} else {
	set ::script_dir [file normalize [pwd]]
}
set ::msgs_dir [file join $::script_dir msgs]

# --- DIAGNOSTIC visuel ---
set _diag "script_dir = $::script_dir\n"
append _diag "msgs_dir   = $::msgs_dir\n"
append _diag "msgs_dir existe : [file isdirectory $::msgs_dir]\n"
foreach _f [glob -nocomplain -directory $::msgs_dir *.msg] {
	append _diag "fichier : $_f\n"
}
#£ tk_messageBox -title "DEBUG chemins" -message $_diag

# Charger tous les mcset d'un fichier langue
proc charger_langue {code} {
	set f [file join $::msgs_dir ${code}.msg]
#£ 	tk_messageBox -title "DEBUG langue" \
#£ 		-message "code=$code\nfichier=$f\nexiste=[file exists $f]"
	if {![file exists $f]} { return 0 }
	namespace eval :: [list source $f]
	::msgcat::mclocale $code
	set ::langue_courante $code
#£ 	tk_messageBox -title "DEBUG après source" \
#£ 		-message "locale=[::msgcat::mclocale]\nmenu_fichier=[::msgcat::mc menu_fichier]"
	return 1
}

# Lister les langues disponibles d'après les fichiers .msg présents
proc langues_disponibles {} {
	set codes {}
	foreach f [glob -nocomplain -directory $::msgs_dir *.msg] {
		lappend codes [file rootname [file tail $f]]
	}
	return [lsort $codes]
}

proc nom_langue {code} {
	switch $code {
		fr	  { return "Français" }
		en	  { return "English"  }
		es	  { return "Español"  }
		ido	  { return "Ido linguo"  }
		de	  { return "Deutsch" }
		ru	  { return "Русский" }
		default { return $code	  }
	}
}

# Raccourci global — toujours explicite pour éviter les pièges de namespace
proc T {key} { return [::msgcat::mc $key] }

# Charger la langue : locale système -> fr -> première disponible
set ::langue_courante fr
set _sys [string range [::msgcat::mclocale] 0 1]
if {![charger_langue $_sys]} {
	if {![charger_langue fr]} {
		set _first [lindex [langues_disponibles] 0]
		if {$_first ne ""} { charger_langue $_first }
	}
}

# =============================================================================
# === Configuration ============================================================
# =============================================================================
set thumb_size		   64
set images_list		  {}
set current_dir		  ""
array set img_fichiers   {}
set image_droite_fichier ""
set rotation_angle	   0
set zoom_factor		  1.0

# === Détection ImageMagick ===================================================
proc detecter_imagemagick {} {
	if {![catch {exec magick  -version}]} { return "magick"  }
	if {![catch {exec convert -version}]} { return "convert" }
	return ""
}
set ::im_cmd [detecter_imagemagick]

# =============================================================================
# === Construction/reconstruction du menu =====================================
# =============================================================================
proc construire_menu {} {
	catch {destroy .menubar}
	menu .menubar
	. configure -menu .menubar

	# --- Fichier ---
	menu .menubar.fichier -tearoff 0
	.menubar add cascade -label [T menu_fichier] -menu .menubar.fichier
	.menubar.fichier add command -label [T menu_ouvrir]  -command choisir_repertoire
	.menubar.fichier add separator
	.menubar.fichier add command -label [T menu_quitter] -command exit

	# --- Affichage ---
	menu .menubar.affichage -tearoff 0
	.menubar add cascade -label [T menu_affichage] -menu .menubar.affichage

	.menubar.affichage add command \
		-label [T menu_taille]  -command afficher_taille_reelle -state disabled
	.menubar.affichage add command \
		-label [T menu_ajuster] -command afficher_ajuste		-state disabled
	.menubar.affichage add separator

	if {$::im_cmd ne ""} {
		.menubar.affichage add command \
			-label [T menu_rot_droite] -command {rotation  90} -state disabled
		.menubar.affichage add command \
			-label [T menu_rot_gauche] -command {rotation -90} -state disabled
		.menubar.affichage add command \
			-label [T menu_flip]	   -command flip_horizontal -state disabled
	} else {
		.menubar.affichage add command \
			-label "[T menu_rot_droite]  [T menu_im_requis]" -state disabled
		.menubar.affichage add command \
			-label "[T menu_rot_gauche]  [T menu_im_requis]" -state disabled
		.menubar.affichage add command \
			-label "[T menu_flip]  [T menu_im_requis]"	   -state disabled
	}
	.menubar.affichage add separator
	.menubar.affichage add command \
		-label [T menu_zoom_avant]   -command {zoom 1.25} -state disabled
	.menubar.affichage add command \
		-label [T menu_zoom_arriere] -command {zoom 0.80} -state disabled
	.menubar.affichage add command \
		-label [T menu_zoom_reset]   -command zoom_reset  -state disabled

	# --- Langue ---
	menu .menubar.langue -tearoff 0
	.menubar add cascade -label [T menu_langue] -menu .menubar.langue
	foreach code [langues_disponibles] {
		.menubar.langue add radiobutton \
			-label	[nom_langue $code] \
			-variable ::langue_courante  \
			-value	$code			  \
			-command  [list changer_langue $code]
	}

	# --- Aide ---
	menu .menubar.aide -tearoff 0
	.menubar add cascade -label [T menu_aide] -menu .menubar.aide
	.menubar.aide add command -label [T menu_aide_aide] \
		-command { puts "TODO: aide" }
	.menubar.aide add separator
	.menubar.aide add command -label [T menu_apropos] \
		-command { puts "TODO: à propos" }

	# Réactiver si une image est déjà ouverte
	if {$::image_droite_fichier ne ""} { activer_menu_image }
}

proc changer_langue {code} {
	charger_langue $code
	construire_menu
	wm title . [T app_title]
}

proc activer_menu_image {} {
	.menubar.affichage entryconfigure [T menu_taille]		-state normal
	.menubar.affichage entryconfigure [T menu_ajuster]	   -state normal
	if {$::im_cmd ne ""} {
		.menubar.affichage entryconfigure [T menu_rot_droite] -state normal
		.menubar.affichage entryconfigure [T menu_rot_gauche] -state normal
		.menubar.affichage entryconfigure [T menu_flip]	   -state normal
	}
	.menubar.affichage entryconfigure [T menu_zoom_avant]   -state normal
	.menubar.affichage entryconfigure [T menu_zoom_arriere] -state normal
	.menubar.affichage entryconfigure [T menu_zoom_reset]   -state normal
}

proc desactiver_menu_image {} {
	.menubar.affichage entryconfigure [T menu_taille]		-state disabled
	.menubar.affichage entryconfigure [T menu_ajuster]	   -state disabled
	if {$::im_cmd ne ""} {
		.menubar.affichage entryconfigure [T menu_rot_droite] -state disabled
		.menubar.affichage entryconfigure [T menu_rot_gauche] -state disabled
		.menubar.affichage entryconfigure [T menu_flip]	   -state disabled
	}
	.menubar.affichage entryconfigure [T menu_zoom_avant]   -state disabled
	.menubar.affichage entryconfigure [T menu_zoom_arriere] -state disabled
	.menubar.affichage entryconfigure [T menu_zoom_reset]   -state disabled
}

# =============================================================================
# === Fenêtre et widgets =======================================================
# =============================================================================
wm title	. [T app_title]
wm geometry . "1200x800"

construire_menu

if {$::im_cmd eq ""} {
	tk_messageBox -type ok -icon warning \
		-title   [T im_absent_titre] \
		-message [T im_absent_msg]   \
		-detail  [T im_absent_detail]
}

frame .main
pack  .main -fill both -expand 1

panedwindow .main.pw -orient horizontal -sashrelief raised -sashwidth 4
pack .main.pw -fill both -expand 1

# --- Panneau gauche (miniatures) ---
frame .main.pw.left
.main.pw add .main.pw.left -minsize 80

text .main.pw.left.txt \
	-wrap none \
	-xscrollcommand {.main.pw.left.sbh set} \
	-yscrollcommand {.main.pw.left.sbv set} \
	-state disabled -bg aquamarine -cursor arrow
scrollbar .main.pw.left.sbv -orient vertical   -command {.main.pw.left.txt yview}
scrollbar .main.pw.left.sbh -orient horizontal -command {.main.pw.left.txt xview}
grid .main.pw.left.txt .main.pw.left.sbv -sticky nsew
grid .main.pw.left.sbh				   -sticky ew
grid columnconfigure .main.pw.left 0 -weight 1
grid rowconfigure	.main.pw.left 0 -weight 1

# --- Panneau droit (image agrandie) ---
frame .main.pw.right
.main.pw add .main.pw.right -minsize 200

text .main.pw.right.txt \
	-wrap none \
	-xscrollcommand {.main.pw.right.sbh set} \
	-yscrollcommand {.main.pw.right.sbv set} \
	-state disabled -bg ivory
scrollbar .main.pw.right.sbv -orient vertical   -command {.main.pw.right.txt yview}
scrollbar .main.pw.right.sbh -orient horizontal -command {.main.pw.right.txt xview}
grid .main.pw.right.txt .main.pw.right.sbv -sticky nsew
grid .main.pw.right.sbh					-sticky ew
grid columnconfigure .main.pw.right 0 -weight 1
grid rowconfigure	.main.pw.right 0 -weight 1

# === Binding clic sur miniature ===
bind .main.pw.left.txt <Button-1> {
	set _idx [.main.pw.left.txt index @%x,%y]
	if {[catch {set _nom [.main.pw.left.txt image cget $_idx -name]}]} { return }
	if {[info exists img_fichiers($_nom)]} { afficher_image $img_fichiers($_nom) }
}

# === Ajustement sash 10%/90% ===
proc ajuster_sash {} {
	set w [winfo width .main.pw]
	if {$w > 10} {
		.main.pw sash place 0 [expr {int($w * 0.10)}] 0
	} else {
		after 100 ajuster_sash
	}
}
bind . <Map>	   { after 200 ajuster_sash }
bind . <Configure> { after 50  ajuster_sash }

# =============================================================================
# === Procs métier =============================================================
# =============================================================================
proc est_image {fichier} {
	set ext [string tolower [file extension $fichier]]
	return [expr {$ext in {.jpg .jpeg .png .gif .bmp .tif .tiff .ico .webp}}]
}

proc creer_miniature {fichier} {
	global thumb_size
	set orig [image create photo -file $fichier]
	set ow [image width $orig]
	set oh [image height $orig]
	set thumb [image create photo -width $thumb_size -height $thumb_size]
	if {$ow == 0 || $oh == 0} { image delete $orig ; return $thumb }
	set scale [expr {max(double($thumb_size)/$ow, double($thumb_size)/$oh)}]
	set inter [image create photo]
	if {$scale >= 1.0} {
		set z [expr {max(1, int(ceil($scale)))}]
		$inter copy $orig -zoom $z $z
	} else {
		set s [expr {max(1, int(floor(1.0/$scale)))}]
		$inter copy $orig -subsample $s $s
	}
	set iw [image width $inter] ; set ih [image height $inter]
	set x0 [expr {max(0, ($iw-$thumb_size)/2)}]
	set y0 [expr {max(0, ($ih-$thumb_size)/2)}]
	$thumb copy $inter \
		-from $x0 $y0 [expr {min($iw,$x0+$thumb_size)}] [expr {min($ih,$y0+$thumb_size)}] \
		-to 0 0
	image delete $inter ; image delete $orig
	return $thumb
}

proc choisir_repertoire {} {
	global current_dir
	set dir [tk_chooseDirectory \
		-title	  [T dlg_choisir_rep] \
		-initialdir $current_dir]
	if {$dir ne ""} { set current_dir $dir ; charger_images $dir }
}

proc charger_images {dir} {
	global images_list img_fichiers
	.main.pw.left.txt  configure -state normal
	.main.pw.left.txt  delete 1.0 end
	.main.pw.right.txt configure -state normal
	.main.pw.right.txt delete 1.0 end
	.main.pw.right.txt configure -state disabled
	desactiver_menu_image
	foreach img $images_list { catch {image delete $img} }
	set images_list {}
	array unset img_fichiers
	set count 0
	foreach f [lsort [glob -nocomplain -directory $dir *]] {
		if {![est_image $f]} continue
		if {[catch {
			set thumb [creer_miniature $f]
			lappend images_list $thumb
			set nom "thumb_$count"
			.main.pw.left.txt image create end \
				-image $thumb -padx 4 -pady 4 -align center -name $nom
			.main.pw.left.txt insert end "\n"
			set img_fichiers($nom) $f
			incr count
		} err]} { puts "Erreur '$f' : $err" }
	}
	.main.pw.left.txt configure -state disabled
	set s [expr {$count > 1 ? "s" : ""}]
	wm title . [format [T titre_images] $dir $count $s]
	if {$count == 0} {
		tk_messageBox -type ok -icon warning \
			-title   [T dlg_rep_vide_titre] \
			-message [T dlg_rep_vide_msg]   \
			-detail  $dir
	}
}

proc afficher_image {fichier} {
	global image_droite_fichier rotation_angle zoom_factor
	set image_droite_fichier $fichier
	set rotation_angle 0
	set zoom_factor	1.0
	.main.pw.right.txt configure -state normal
	.main.pw.right.txt delete 1.0 end
	if {[catch {
		set img [image create photo -file $fichier]
		.main.pw.right.txt image create end -image $img -padx 4 -pady 4
		set ::image_droite $img
	} err]} { .main.pw.right.txt insert end "Erreur : $err" }
	.main.pw.right.txt configure -state disabled
	activer_menu_image
}

proc afficher_taille_reelle {} {
	global image_droite_fichier zoom_factor
	if {$image_droite_fichier eq ""} return
	set zoom_factor 1.0
	.main.pw.right.txt configure -state normal
	.main.pw.right.txt delete 1.0 end
	if {[catch {
		set img [image create photo -file $image_droite_fichier]
		.main.pw.right.txt image create end -image $img -padx 4 -pady 4
		set ::image_droite $img
	} err]} { .main.pw.right.txt insert end "Erreur : $err" }
	.main.pw.right.txt configure -state disabled
}

proc afficher_ajuste {} {
	global image_droite_fichier
	if {$image_droite_fichier eq ""} return
	set dw [expr {max(1,[winfo width  .main.pw.right.txt]-12)}]
	set dh [expr {max(1,[winfo height .main.pw.right.txt]-12)}]
	if {[catch {
		set orig  [image create photo -file $image_droite_fichier]
		set ow	[image width $orig] ; set oh [image height $orig]
		set scale [expr {min(double($dw)/$ow, double($dh)/$oh)}]
		set nw [expr {max(1,int($ow*$scale))}]
		set nh [expr {max(1,int($oh*$scale))}]
		set ajuste [image create photo -width $nw -height $nh]
		set inter  [image create photo]
		if {$scale >= 1.0} {
			set z [expr {max(1,int(ceil($scale)))}]
			$inter copy $orig -zoom $z $z
		} else {
			set s [expr {max(1,int(floor(1.0/$scale)))}]
			$inter copy $orig -subsample $s $s
		}
		set iw [image width $inter] ; set ih [image height $inter]
		set x0 [expr {max(0,($iw-$nw)/2)}] ; set y0 [expr {max(0,($ih-$nh)/2)}]
		$ajuste copy $inter \
			-from $x0 $y0 [expr {min($iw,$x0+$nw)}] [expr {min($ih,$y0+$nh)}] -to 0 0
		image delete $inter ; image delete $orig
		afficher_photo $ajuste
	} err]} { puts "Erreur ajustement : $err" }
}

# =============================================================================
# === Utilitaires ImageMagick ==================================================
# =============================================================================
proc get_tmpdir {} {
	if {[info exists ::env(TEMP)]} { return $::env(TEMP) }
	if {[info exists ::env(TMP)]}  { return $::env(TMP)  }
	return "/tmp"
}

proc afficher_photo {img} {
	.main.pw.right.txt configure -state normal
	.main.pw.right.txt delete 1.0 end
	.main.pw.right.txt image create end -image $img -padx 4 -pady 4
	set ::image_droite $img
	.main.pw.right.txt configure -state disabled
}

proc im_convert {args} {
	if {$::im_cmd eq "magick"} {
		exec magick convert {*}$args
	} else {
		exec convert {*}$args
	}
}

proc rotation {sens} {
	global image_droite_fichier rotation_angle
	if {$image_droite_fichier eq ""} return
	if {$::im_cmd eq ""} {
		tk_messageBox -type ok -icon error \
			-title [T im_absent_titre] -message [T im_absent_op]
		return
	}
	set rotation_angle [expr {($rotation_angle + $sens + 360) % 360}]
	set tmp [file join [get_tmpdir] "__visto_rot_tmp__.png"]
	if {[catch {
		im_convert -rotate $rotation_angle $image_droite_fichier $tmp
		afficher_photo [image create photo -file $tmp]
		file delete -force $tmp
	} err]} {
		catch {file delete -force $tmp}
		tk_messageBox -type ok -icon error \
			-title [T err_titre] -message [T err_rotation] -detail $err
	}
}

proc flip_horizontal {} {
	global image_droite_fichier
	if {$image_droite_fichier eq ""} return
	if {$::im_cmd eq ""} {
		tk_messageBox -type ok -icon error \
			-title [T im_absent_titre] -message [T im_absent_op]
		return
	}
	set tmp [file join [get_tmpdir] "__visto_flip_tmp__.png"]
	if {[catch {
		im_convert -flop $image_droite_fichier $tmp
		afficher_photo [image create photo -file $tmp]
		file delete -force $tmp
	} err]} {
		catch {file delete -force $tmp}
		tk_messageBox -type ok -icon error \
			-title [T err_titre] -message [T err_flip] -detail $err
	}
}

proc zoom {facteur} {
	global image_droite_fichier zoom_factor
	if {$image_droite_fichier eq ""} return
	set zoom_factor [expr {max(0.05, min(16.0, $zoom_factor * $facteur))}]
	appliquer_zoom
}

proc zoom_reset {} {
	global zoom_factor
	set zoom_factor 1.0
	appliquer_zoom
}

proc appliquer_zoom {} {
	global image_droite_fichier zoom_factor
	if {$image_droite_fichier eq ""} return
	set pct [expr {int(round($zoom_factor * 100))}]
	if {$::im_cmd ne ""} {
		set tmp [file join [get_tmpdir] "__visto_zoom_tmp__.png"]
		if {[catch {
			set orig [image create photo -file $image_droite_fichier]
			set nw [expr {max(1,int(round([image width  $orig]*$zoom_factor)))}]
			set nh [expr {max(1,int(round([image height $orig]*$zoom_factor)))}]
			image delete $orig
			im_convert -resize ${nw}x${nh}! $image_droite_fichier $tmp
			afficher_photo [image create photo -file $tmp]
			file delete -force $tmp
		} err]} {
			catch {file delete -force $tmp}
			puts "Erreur zoom IM : $err"
		}
	} else {
		if {[catch {
			set orig [image create photo -file $image_droite_fichier]
			set ow [image width $orig] ; set oh [image height $orig]
			set nw [expr {max(1,int(round($ow*$zoom_factor)))}]
			set nh [expr {max(1,int(round($oh*$zoom_factor)))}]
			set result [image create photo -width $nw -height $nh]
			set inter  [image create photo]
			if {$zoom_factor >= 1.0} {
				set z [expr {max(1,int(ceil($zoom_factor)))}]
				$inter copy $orig -zoom $z $z
				set iw [image width $inter] ; set ih [image height $inter]
				set x0 [expr {max(0,($iw-$nw)/2)}]
				set y0 [expr {max(0,($ih-$nh)/2)}]
				$result copy $inter \
					-from $x0 $y0 [expr {$x0+$nw}] [expr {$y0+$nh}] -to 0 0
			} else {
				set s [expr {max(1,int(round(1.0/$zoom_factor)))}]
				$inter copy $orig -subsample $s $s
				set iw [image width $inter] ; set ih [image height $inter]
				$result copy $inter \
					-from 0 0 [expr {min($iw,$nw)}] [expr {min($ih,$nh)}] -to 0 0
			}
			image delete $inter ; image delete $orig
			afficher_photo $result
		} err]} { puts "Erreur zoom Tcl : $err" }
	}
	wm title . [format [T titre_zoom] [file tail $image_droite_fichier] $pct]
}
