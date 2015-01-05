/*
 * Copyright (C) 2011-2012 Robert Ancell
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class Mines : Gtk.Application
{
    /* Settings keys */
    private Settings settings;
    private const string KEY_XSIZE = "xsize";
    private const int XSIZE_MIN = 4;
    private const int XSIZE_MAX = 100;
    private const string KEY_YSIZE = "ysize";
    private const int YSIZE_MIN = 4;
    private const int YSIZE_MAX = 100;
    private const string KEY_NMINES = "nmines";
    private const string KEY_MODE = "mode";

    /* For command-line options */
    private static int game_mode = -1;

    /* Keys shared with MinefieldView */
    public static const string KEY_USE_QUESTION_MARKS = "use-question-marks";
    public static const string KEY_USE_OVERMINE_WARNING = "use-overmine-warning";
    public static const string KEY_USE_AUTOFLAG = "use-autoflag";

    private Gtk.Widget main_screen;
    private Gtk.Button play_pause_button;
    private Gtk.Label play_pause_label;
    private Gtk.Button replay_button;
    private Gtk.Button high_scores_button;
    private Gtk.Button new_game_button;
    private Gtk.AspectFrame minefield_aspect;
    private Gtk.Overlay minefield_overlay;
    private Gtk.Box paused_box;
    private Gtk.ScrolledWindow scrolled;
    private Gtk.Stack stack;

    private Gtk.Label clock_label;

    private Menu app_main_menu;

    /* Main window */
    private Gtk.Window window;
    private int window_width;
    private int window_height;
    private bool is_maximized;

    /* true when the user has requested the game to pause. */
    private bool pause_requested;

    /* true when the next configure event should be ignored. */
    private bool window_skip_configure;

    /* Game scores */
    private Games.Scores.Context? context = null;

    /* Minefield being played */
    private Minefield minefield;

    /* Minefield widget */
    private MinefieldView minefield_view;

    /* Game status */
    private Gtk.Label flag_label;

    private Gtk.SpinButton mines_spin;
    private SimpleAction new_game_action;
    private SimpleAction repeat_size_action;
    private SimpleAction pause_action;
    private Gtk.AspectFrame new_game_screen;
    private Gtk.AspectFrame custom_game_screen;

    private const OptionEntry[] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print release version and exit"), null },
        { "small",  0, 0, OptionArg.NONE, null, N_("Small game"), null },
        { "medium", 0, 0, OptionArg.NONE, null, N_("Medium game"), null },
        { "big",    0, 0, OptionArg.NONE, null, N_("Big game"), null },
        { null }
    };

    private const GLib.ActionEntry[] action_entries =
    {
        { "new-game",           new_game_cb                                 },
        { "repeat-size",        repeat_size_cb                              },
        { "pause",              toggle_pause_cb                             },
        { "scores",             scores_cb                                   },
        { "quit",               quit_cb                                     },
        { "help",               help_cb                                     },
        { "about",              about_cb                                    }
    };

    public Mines ()
    {
        Object (application_id: "org.gnome.mines", flags: ApplicationFlags.FLAGS_NONE);

        add_main_option_entries (option_entries);
    }

    protected override void startup ()
    {
        base.startup ();

        Environment.set_application_name (_("Mines"));

        settings = new Settings ("org.gnome.mines");
        settings.delay ();

        if (game_mode != -1)
            settings.set_int (KEY_MODE, game_mode);

        Gtk.Window.set_default_icon_name ("gnome-mines");

        var css_provider = new Gtk.CssProvider ();
        var css_path = Path.build_filename (DATA_DIRECTORY, "gnome-mines.css");
        try
        {
            css_provider.load_from_path (css_path);
        }
        catch (GLib.Error e)
        {
            warning ("Error loading css styles from %s: %s", css_path, e.message);
        }

        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        var ui_builder = new Gtk.Builder ();
        try
        {
            ui_builder.add_from_file (Path.build_filename (DATA_DIRECTORY, "interface.ui", null));
        }
        catch (Error e)
        {
            warning ("Could not load game UI: %s", e.message);
        }

        Gtk.IconTheme.get_default ().append_search_path (DATA_DIRECTORY);

        add_action_entries (action_entries, this);
        new_game_action = lookup_action ("new-game") as SimpleAction;
        new_game_action.set_enabled (false);
        repeat_size_action = lookup_action ("repeat-size") as SimpleAction;
        repeat_size_action.set_enabled (false);
        pause_action = lookup_action ("pause") as SimpleAction;
        pause_action.set_enabled (false);
        add_action (settings.create_action (KEY_USE_OVERMINE_WARNING));
        add_action (settings.create_action (KEY_USE_QUESTION_MARKS));

        window = (Gtk.ApplicationWindow) ui_builder.get_object ("main_window");
        window.configure_event.connect (window_configure_event_cb);
        window.window_state_event.connect (window_state_event_cb);
        window.focus_out_event.connect (window_focus_out_event_cb);
        window.focus_in_event.connect (window_focus_in_event_cb);
        window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            window.maximize ();
        add_window (window);



        var desktop = Environment.get_variable ("XDG_CURRENT_DESKTOP");
        if (desktop == null || desktop != "Unity")
        {
            var headerbar = new Gtk.HeaderBar ();
            headerbar.show_close_button = true;
            headerbar.set_title (_("Mines"));
            headerbar.show ();
            window.set_titlebar (headerbar);
        }

        bool shell_shows_menubar;
        Gtk.Settings.get_default ().get ("gtk-shell-shows-menubar", out shell_shows_menubar);
        if (!shell_shows_menubar)
        {
            var menu = new Menu ();
            app_main_menu = new Menu ();
            menu.append_section (null, app_main_menu);
            app_main_menu.append (_("_New Game"), "app.new-game");
            app_main_menu.append (_("_Scores"), "app.scores");
            var section = new Menu ();
            menu.append_section (null, section);
            section.append (_("_Show Warnings"), "app.%s".printf (KEY_USE_OVERMINE_WARNING));
            section.append (_("_Use Question Flags"), "app.%s".printf (KEY_USE_QUESTION_MARKS));
            section = new Menu ();
            menu.append_section (null, section);
            section.append (_("_Help"), "app.help");
            section.append (_("_About"), "app.about");
            section.append (_("_Quit"), "app.quit");
            set_app_menu (menu);
        }
        else
        {
            var menu = new Menu ();
            var mines_menu = new Menu ();
            menu.append_submenu (_("_Mines"), mines_menu);
            mines_menu.append (_("_New Game"), "app.new-game");
            mines_menu.append (_("_Scores"), "app.scores");
            mines_menu.append (_("_Show Warnings"), "app.%s".printf (KEY_USE_OVERMINE_WARNING));
            mines_menu.append (_("_Use Question Flags"), "app.%s".printf (KEY_USE_QUESTION_MARKS));
            mines_menu.append (_("_Quit"), "app.quit");
            var help_menu = new Menu ();
            menu.append_submenu (_("_Help"), help_menu);
            help_menu.append (_("_Contents"), "app.help");
            help_menu.append (_("_About"), "app.about");
            set_menubar (menu);
        }

        set_accels_for_action ("app.new-game", {"<Primary>n"});
        set_accels_for_action ("app.repeat-size", {"<Primary>r"});
        set_accels_for_action ("app.pause", {"Pause"});
        set_accels_for_action ("app.help", {"F1"});
        set_accels_for_action ("app.quit", {"<Primary>q", "<Primary>w"});

        minefield_view = new MinefieldView (settings);
        minefield_view.show ();

        stack = (Gtk.Stack) ui_builder.get_object ("stack");

        scrolled = new Gtk.ScrolledWindow (null, null);
        scrolled.show ();
        scrolled.add (minefield_view);

        minefield_overlay = (Gtk.Overlay) ui_builder.get_object ("minefield_overlay");
        minefield_overlay.add (scrolled);
        minefield_overlay.show ();

        minefield_aspect = (Gtk.AspectFrame) ui_builder.get_object ("minefield_aspect");
        minefield_aspect.show ();

        paused_box = (Gtk.Box) ui_builder.get_object ("paused_box");
        paused_box.button_press_event.connect (view_button_press_event);

        minefield_overlay.add_overlay (paused_box);

        main_screen = (Gtk.Widget) ui_builder.get_object ("main_screen");
        main_screen.show_all ();

        /* Initialize New Game Screen */
        startup_new_game_screen (ui_builder);

        /* Initialize Custom Game Screen */
        startup_custom_game_screen (ui_builder);

	context = new Games.Scores.Context (_("Mines"), "Game", window, Games.Scores.Style.TIME_ASCENDING);

        flag_label = (Gtk.Label) ui_builder.get_object ("flag_label");
        clock_label = (Gtk.Label) ui_builder.get_object ("clock_label");

        play_pause_button = (Gtk.Button) ui_builder.get_object ("play_pause_button");
        play_pause_label = (Gtk.Label) ui_builder.get_object ("play_pause_label");

        high_scores_button = (Gtk.Button) ui_builder.get_object ("high_scores_button");
        replay_button = (Gtk.Button) ui_builder.get_object ("replay_button");
        new_game_button = (Gtk.Button) ui_builder.get_object ("new_game_button");

        if (game_mode != -1)
            start_game ();
    }

    private void startup_new_game_screen (Gtk.Builder builder)
    {
        new_game_screen =  (Gtk.AspectFrame) builder.get_object ("new_game_screen");

        var button = (Gtk.Button) builder.get_object ("small_size_btn");
        button.clicked.connect (small_size_clicked_cb);

        var label = new Gtk.Label (null);
        label.set_markup (make_minefield_description (8, 8, 10));
        label.set_justify (Gtk.Justification.CENTER);
        button.add (label);

        button = (Gtk.Button) builder.get_object ("medium_size_btn");
        button.clicked.connect (medium_size_clicked_cb);

        label = new Gtk.Label (null);
        label.set_markup (make_minefield_description (16, 16, 40));
        label.set_justify (Gtk.Justification.CENTER);
        button.add (label);

        button = (Gtk.Button) builder.get_object ("large_size_btn");
        button.clicked.connect (large_size_clicked_cb);

        label = new Gtk.Label (null);
        label.set_markup (make_minefield_description (30, 16, 99));
        label.set_justify (Gtk.Justification.CENTER);
        button.add (label);

        button = (Gtk.Button) builder.get_object ("custom_size_btn");
        button.clicked.connect (show_custom_game_screen);

        label = new Gtk.Label (null);
        label.set_markup_with_mnemonic ("<span size='xx-large' weight='heavy'>?</span>\n" + dpgettext2 (null, "board size", _("Custom")));
        label.set_justify (Gtk.Justification.CENTER);
        button.add (label);

        new_game_screen.show_all ();
    }

    private void startup_custom_game_screen (Gtk.Builder builder)
    {
        custom_game_screen =  (Gtk.AspectFrame) builder.get_object ("custom_game_screen");

        var field_width_entry = (Gtk.SpinButton) builder.get_object ("width_spin_btn");
        field_width_entry.set_range (XSIZE_MIN, XSIZE_MAX);
        field_width_entry.value_changed.connect (xsize_spin_cb);
        field_width_entry.set_increments (1, 1);
        field_width_entry.set_value (settings.get_int (KEY_XSIZE));

        var field_height_entry = (Gtk.SpinButton) builder.get_object ("height_spin_btn");
        field_height_entry.set_range (YSIZE_MIN, YSIZE_MAX);
        field_height_entry.value_changed.connect (ysize_spin_cb);
        field_height_entry.set_increments (1, 1);
        field_height_entry.set_value (settings.get_int (KEY_YSIZE));

        mines_spin = (Gtk.SpinButton) builder.get_object ("mines_spin_btn");
        mines_spin.set_range (1, 100);
        mines_spin.set_increments (1, 1);
        mines_spin.value_changed.connect (mines_spin_cb);
        set_mines_limit ();

        var button = (Gtk.Button) builder.get_object ("cancel_btn");
        button.clicked.connect (show_new_game_screen);

        button = (Gtk.Button) builder.get_object ("play_game_btn");
        button.clicked.connect (custom_size_clicked_cb);

        custom_game_screen.show_all ();
    }

    private bool window_configure_event_cb (Gdk.EventConfigure event)
    {
        if (!is_maximized && !window_skip_configure)
        {
            window_width = event.width;
            window_height = event.height;
        }

        window_skip_configure = false;

        return false;
    }

    private bool window_state_event_cb (Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        return false;
    }

    private bool window_focus_out_event_cb (Gdk.EventFocus event)
    {
        if (minefield != null && minefield.is_clock_started ())
            minefield.paused = true;

        return false;
    }

    private bool window_focus_in_event_cb (Gdk.EventFocus event)
    {
        if (minefield != null && !pause_requested)
            minefield.paused = false;

        return false;
    }

    private string make_minefield_description (int width, int height, int n_mines)
    {
        var size_label = "%d × %d".printf (width, height);
        var mines_label = ngettext ("<b>%d</b> mine", "<b>%d</b> mines", n_mines).printf (n_mines);
        return "<span size='x-large' weight='ultrabold'>%s</span>\n%s".printf (size_label, mines_label);
    }

    public void start ()
    {
        window.show ();
        show_new_game_screen ();
    }

    protected override void shutdown ()
    {
        base.shutdown ();

        /* Save window state */
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", is_maximized);
        settings.apply ();
    }

    protected override int handle_local_options (GLib.VariantDict options)
    {
        if (options.contains ("version"))
        {
            /* NOTE: Is not translated so can be easily parsed */
            stderr.printf ("%1$s %2$s\n", "gnome-mines", VERSION);
            return Posix.EXIT_SUCCESS;
        }

        if (options.contains ("small"))
            game_mode = 0;
        if (options.contains ("medium"))
            game_mode = 1;
        if (options.contains ("big"))
            game_mode = 2;

        /* Activate */
        return -1;
    }

    protected override void activate ()
    {
        window.present ();
    }

    private bool view_button_press_event (Gtk.Widget widget, Gdk.EventButton event)
    {
        /* Cancel pause on click */
        if (minefield.paused)
        {
            minefield.paused = false;
            pause_requested = false;
            return true;
        }

        return false;
    }

    private void quit_cb ()
    {
        window.destroy ();
    }

    private void update_flag_label ()
    {
        flag_label.set_text ("%u/%u".printf (minefield.n_flags, minefield.n_mines));
    }

    private int show_scores ()
    {
        /*
        dialog.modal = true;
        dialog.transient_for = window;

        var result = dialog.run ();
        dialog.destroy ();

        return result;*/
	print ("Dialog\n");
	context.run_dialog ();
	return 1;
    }

    private void scores_cb ()
    {
        show_scores ();
    }

    private void show_custom_game_screen ()
    {
        stack.visible_child_name = "custom_game";
    }

    private bool can_start_new_game ()
    {
        if (minefield != null && minefield.n_cleared > 0 && !minefield.exploded && !minefield.is_complete)
        {
            var was_paused = minefield.paused;
            minefield.paused = true;

            var dialog = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", _("Do you want to start a new game?"));
            dialog.secondary_text = (_("If you start a new game, your current progress will be lost."));
            dialog.add_buttons (_("Keep Current Game"), Gtk.ResponseType.DELETE_EVENT,
                                _("Start New Game"), Gtk.ResponseType.ACCEPT,
                                null);
            var result = dialog.run ();
            dialog.destroy ();
            if (result != Gtk.ResponseType.ACCEPT)
            {
                minefield.paused = was_paused;
                return false;
            }
        }
        return true;
    }

    private void show_new_game_screen ()
    {
        if (stack.visible_child_name == "new_game")
            return;

        if (minefield != null)
        {
            minefield.paused = true;
            pause_requested = false;
            SignalHandler.disconnect_by_func (minefield, null, this);
        }
        minefield = null;

        window.resize (window_width, window_height);

        new_game_button.show ();

        new_game_action.set_enabled (false);
        repeat_size_action.set_enabled (false);
        pause_action.set_enabled (false);

        stack.visible_child_name = "new_game";
    }

    private void start_game ()
    {
        window_skip_configure = true;
        minefield_view.has_focus = true;

        play_pause_button.hide ();
        replay_button.hide ();
        new_game_button.hide ();
        high_scores_button.hide ();

        tick_cb ();

        int x, y, n;
        switch (settings.get_int (KEY_MODE))
        {
        case 0:
            x = 8;
            y = 8;
            n = 10;
            break;
        case 1:
            x = 16;
            y = 16;
            n = 40;
            break;
        case 2:
            x = 30;
            y = 16;
            n = 99;
            break;
        default:
        case 3:
            x = settings.get_int (KEY_XSIZE).clamp (XSIZE_MIN, XSIZE_MAX);
            y = settings.get_int (KEY_YSIZE).clamp (YSIZE_MIN, YSIZE_MAX);
            n = settings.get_int (KEY_NMINES).clamp (1, x * y - 10);
            break;
        }

        if (minefield != null)
            SignalHandler.disconnect_by_func (minefield, null, this);
        minefield = new Minefield (x, y, n);
        minefield.marks_changed.connect (marks_changed_cb);
        minefield.explode.connect (explode_cb);
        minefield.cleared.connect (cleared_cb);
        minefield.tick.connect (tick_cb);
        minefield.paused_changed.connect (paused_changed_cb);
        minefield.clock_started.connect (clock_started_cb);

        minefield_aspect.ratio = (float)x / y;
        minefield_view.minefield = minefield;
        int request_x = -1, request_y = -1;
        if  (window.get_allocated_width () - scrolled.get_allocated_width () + 30 * x < Gdk.Screen.width ()) {
            request_x = 30 * x;
        } else {
            request_x = Gdk.Screen.width () - window.get_allocated_width () + scrolled.get_allocated_width ();
        }
        if  (window.get_allocated_height () - scrolled.get_allocated_height () + 30 * y < Gdk.Screen.height ()) {
            request_y = 30 * y;
        } else {
            request_y = Gdk.Screen.height () - window.get_allocated_height () + scrolled.get_allocated_height ();
        }
        minefield_aspect.set_size_request (request_x, request_y);
        update_flag_label ();

        new_game_action.set_enabled (true);
        repeat_size_action.set_enabled (true);
        pause_action.set_enabled (true);

        minefield.paused = false;
        pause_requested = false;

        stack.visible_child_name = "game";
    }

    private void new_game_cb ()
    {
        if (can_start_new_game ())
            show_new_game_screen ();
    }

    private void repeat_size_cb ()
    {
        if (can_start_new_game ())
            start_game ();
    }

    private void toggle_pause_cb ()
    {
        if (minefield.paused && !pause_requested)
        {
            pause_requested = true;
        }
        else
        {
            minefield.paused = !minefield.paused;
            pause_requested = minefield.paused;
        }
    }

    private void paused_changed_cb ()
    {
        if (minefield.paused)
            display_unpause_button ();
        else if (minefield.elapsed > 0)
            display_pause_button ();
        paused_box.visible = minefield.paused;
    }

    private void marks_changed_cb (Minefield minefield)
    {
        update_flag_label ();
    }

    private void explode_cb (Minefield minefield)
    {
        new_game_button.show ();

        replay_button.label = _("Play _Again");
        replay_button.show ();

        high_scores_button.show ();
        pause_action.set_enabled (false);
        play_pause_button.hide ();
    }

    private void cleared_cb (Minefield minefield)
    {
        /*var date = new DateTime.now_local ();
        var duration = (uint) (minefield.elapsed + 0.5);
        var entry = new HistoryEntry (date, minefield.width, minefield.height, minefield.n_mines, duration);
        history.add (entry);
        history.save ();
	
        if (show_scores (entry, true) == Gtk.ResponseType.OK)
            show_new_game_screen ();
        else
        {
            new_game_button.show ();

            replay_button.label = _("Play _Again");
            replay_button.show ();

            high_scores_button.show ();
            pause_action.set_enabled (false);
            play_pause_button.hide ();
        }*/
        var duration = (uint) (minefield.elapsed + 0.5);
	string key = minefield.width.to_string () + minefield.height.to_string () + minefield.n_mines.to_string ();
	context.add_score (duration, new Games.Scores.Category (key, key)) ;
        show_new_game_screen ();
    }

    private void clock_started_cb ()
    {
        display_pause_button ();
    }

    private void tick_cb ()
    {
        var elapsed = 0;
        if (minefield != null)
            elapsed = (int) (minefield.elapsed + 0.5);
        var hours = elapsed / 3600;
        var minutes = (elapsed - hours * 3600) / 60;
        var seconds = elapsed - hours * 3600 - minutes * 60;
        if (hours > 0)
            clock_label.set_text ("%02d∶\xE2\x80\x8E%02d∶\xE2\x80\x8E%02d".printf (hours, minutes, seconds));
        else
            clock_label.set_text ("%02d∶\xE2\x80\x8E%02d".printf (minutes, seconds));
    }

    private void about_cb ()
    {
        string[] authors =
        {
            _("Main game:"),
            "Szekeres Istvan (Pista)",
            "Robert Ancell",
            "Robert Roth",
            "",
            _("Score:"),
            "Horacio J. Peña",
            "",
            _("Resizing and SVG support:"),
            "Steve Chaplin",
            "Callum McKenzie",
            null
        };

        string[] artists =
        {
            "Richard Hoelscher",
            null
        };

        string[] documenters =
        {
            "Ekaterina Gerasimova",
            null
        };

        Gtk.show_about_dialog (window,
                               "name", _("Mines"),
                               "version", VERSION,
                               "comments",
                               _("Clear explosive mines off the board\n\nMines is a part of GNOME Games."),
                               "copyright",
                               "Copyright © 1997–2008 Free Software Foundation, Inc.",
                               "license-type", Gtk.License.GPL_2_0,
                               "authors", authors,
                               "artists", artists,
                               "documenters", documenters,
                               "translator-credits", _("translator-credits"),
                               "logo-icon-name", "gnome-mines", "website",
                               "https://wiki.gnome.org/Apps/Mines",
                               null);
    }

    private float percent_mines ()
    {
        return 100.0f * (float) settings.get_int (KEY_NMINES) / (settings.get_int (KEY_XSIZE) * settings.get_int (KEY_YSIZE));
    }

    private void set_mines_limit ()
    {
        var size = settings.get_int (KEY_XSIZE) * settings.get_int (KEY_YSIZE);
        var max_mines = (int) Math.round (100.0f * (float) (size - 10) / size);
        var min_mines = int.max (1, (int) Math.round (100.0f / size));
        mines_spin.set_range (min_mines, max_mines);
        mines_spin.set_value ((int) Math.round (percent_mines ()));
    }

    private void xsize_spin_cb (Gtk.SpinButton spin)
    {
        var xsize = spin.get_value_as_int ();
        if (xsize == settings.get_int (KEY_XSIZE))
            return;

        settings.set_int (KEY_XSIZE, xsize);
        set_mines_limit ();
    }

    private void ysize_spin_cb (Gtk.SpinButton spin)
    {
        var ysize = spin.get_value_as_int ();
        if (ysize == settings.get_int (KEY_YSIZE))
            return;

        settings.set_int (KEY_YSIZE, ysize);
        set_mines_limit ();
    }

    private void mines_spin_cb (Gtk.SpinButton spin)
    {
        if (Math.fabs (percent_mines () - spin.get_value ()) <= 0.5f)
            return;

        settings.set_int (KEY_NMINES,
                          (int) Math.round (spin.get_value () * (settings.get_int (KEY_XSIZE) * settings.get_int (KEY_YSIZE)) / 100.0f));
    }

    private void set_mode (int mode)
    {
        if (mode != settings.get_int (KEY_MODE))
            settings.set_int (KEY_MODE, mode);

        start_game ();
    }

    private void small_size_clicked_cb ()
    {
        set_mode (0);
    }

    private void medium_size_clicked_cb ()
    {
        set_mode (1);
    }

    private void large_size_clicked_cb ()
    {
        set_mode (2);
    }

    private void custom_size_clicked_cb ()
    {
        set_mode (3);
    }

    private void help_cb ()
    {
        try
        {
            Gtk.show_uri (window.get_screen (), "help:gnome-mines", Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            warning ("Failed to show help: %s", e.message);
        }
    }

    private void display_pause_button ()
    {
        replay_button.hide ();
        new_game_button.hide ();

        play_pause_button.show ();
        play_pause_label.label = _("_Pause");
    }

    private void display_unpause_button ()
    {
        replay_button.label = _("St_art Over");
        replay_button.show ();

        new_game_button.show ();

        play_pause_button.show ();
        play_pause_label.label = _("_Resume");
    }

    public static int main (string[] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);

        var app = new Mines ();
        return app.run (args);
    }
}
