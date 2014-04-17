/* We should probably be using the GIR files, but I can't get them to work in
 * Vala.  This works for now but means it needs to be updated when the library
 * changes -- Robert Ancell */

[CCode (cprefix = "Games", lower_case_cprefix = "games_")]
namespace Scores
{
    [CCode (cheader_filename = "games-scores.h")]
    public void scores_startup ();

    [CCode (cprefix = "GAMES_SCORES_STYLE_", cheader_filename = "games-score.h")]
    public enum ScoreStyle
    {
        PLAIN_DESCENDING,
        PLAIN_ASCENDING,
        TIME_DESCENDING,
        TIME_ASCENDING
    }

    [CCode (cheader_filename = "games-scores.h", destroy_function = "")]
    public struct ScoresCategory
    {
        string key;
        string name;
    }

    [CCode (cheader_filename = "games-score.h")]
    public class Score : GLib.Object
    {
        public Score ();
    }

    [CCode (cheader_filename = "games-scores.h")]
    public class Scores : GLib.Object
    {
        public Scores (string app_name, ScoresCategory[] categories, string? categories_context, string? categories_domain, int default_category_index, ScoreStyle style);
        public void set_category (string category);
        public int add_score (Score score);
        public int add_plain_score (uint32 value);
        public int add_time_score (double value);
        public void update_score (string new_name);
        public void update_score_name (string new_name, string old_name);
        public ScoreStyle get_style ();
        public unowned string get_category ();
        public void add_category (string key, string name);
    }

    [CCode (cprefix = "GAMES_SCORES_", cheader_filename = "games-scores-dialog.h")]
    public enum ScoresButtons
    {
        CLOSE_BUTTON,
        NEW_GAME_BUTTON,
        UNDO_BUTTON,
        QUIT_BUTTON
    }

    [CCode (cheader_filename = "games-scores-dialog.h")]
    public class ScoresDialog : Gtk.Dialog
    {
        public ScoresDialog (Gtk.Window parent_window, Scores scores, string title);
        public void set_category_description (string description);
        public void set_hilight (uint pos);
        public void set_message (string? message);
        public void set_buttons (uint buttons);
    }
}
