SUBDIRS = icons

gsettings_SCHEMAS = org.gnome.mines.gschema.xml
@GSETTINGS_RULES@

man_MANS = gnome-mines.6

pixmapdir   = $(pkgdatadir)
pixmap_DATA = mine.svg exploded.svg overmine.svg \
            1mines.svg 2mines.svg 3mines.svg 4mines.svg \
            5mines.svg 6mines.svg 7mines.svg 8mines.svg \
            flag.svg flag-symbolic.svg maybe.svg


icon_symbolicdir=$(datadir)/icons/hicolor/16x16/actions
icon_symbolic_DATA=flag-symbolic.svg

gnome-mines.css: gnome-mines.css.in Makefile
	$(AM_V_GEN) sed -e "s|\@pkgdatadir\@|$(pkgdatadir)|" $< > $@

cssdir = $(pkgdatadir)
css_in_files = gnome-mines.css.in
css_DATA = $(css_in_files:.css.in=.css)

uidir = $(pkgdatadir)
ui_DATA = interface.ui

desktopdir = $(datadir)/applications
desktop_in_files = gnome-mines.desktop.in
desktop_DATA = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

appstream_in_files = gnome-mines.appdata.xml.in
appstream_XML = $(appstream_in_files:.xml.in=.xml)
@APPSTREAM_XML_RULES@
@INTLTOOL_XML_RULE@

EXTRA_DIST = \
             $(appstream_in_files) \
             $(gsettings_SCHEMAS) \
             $(desktop_in_files) \
             $(man_MANS) \
             $(pixmap_DATA) \
             $(icon_symbolic_DATA) \
             $(css_in_files) \
             $(ui_DATA)

CLEANFILES = \
	$(appstream_XML) \
	$(desktop_DATA) \
	$(css_DATA)

check-local: $(desktop_DATA) \
	$(DESKTOP_FILE_VALIDATE) $(desktop_DATA)

DISTCHECK_CONFIGURE_FLAGS = --enable-appdata-check

-include $(top_srcdir)/git.mk
