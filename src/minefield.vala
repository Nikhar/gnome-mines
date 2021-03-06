/*
 * Copyright (C) 2011-2012 Robert Ancell
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public enum FlagType
{
    NONE,
    FLAG,
    MAYBE
}

private class Location : Object
{
    /* true if contains a mine */
    public bool has_mine = false;
    
    /* true if cleared */
    public bool cleared = false;

    /* Flag */
    public FlagType flag = FlagType.NONE;
}

/* Table of offsets to adjacent squares */
private struct Neighbour
{
    public int x;
    public int y;
}
private static const Neighbour neighbour_map[] =
{
    {-1, 1},
    {0, 1},
    {1, 1},
    {1, 0},
    {1, -1},
    {0, -1},
    {-1, -1},
    {-1, 0}
};

public class Minefield : Object
{
    /* Size of map */
    public uint width = 0;
    public uint height = 0;
    
    /* Number of mines in map */
    public uint n_mines = 0;

    /* State of each location */
    private Location[,] locations;

    /* true if have hit a mine */
    public bool exploded = false;

    /* true if have placed the mines onto the map */
    private bool placed_mines = false;

    /* keep track of flags and cleared squares */
    private uint _n_cleared = 0;
    private uint _n_flags = 0;

    public uint n_cleared
    {
        get { return _n_cleared; }
        set { _n_cleared = value; }
    }

    public bool is_complete
    {
        get { return n_cleared == width * height - n_mines; }
    }

    public uint n_flags
    {
        get { return _n_flags; }
        set { _n_flags = value; }
    }

    /* Game timer */
    private double clock_elapsed;
    private Timer? clock;
    private uint clock_timeout;

    public double elapsed
    {
        get
        {
            if (clock == null)
                return 0.0;
            return clock_elapsed + clock.elapsed ();
        }
    }

    private bool _paused = false;
    public bool paused
    {
        set
        {
            if (is_complete || exploded)
                return;

            if (clock != null)
            {
                if (value && !_paused)
                    stop_clock ();
                else if (!value && _paused)
                    continue_clock ();
            }

            _paused = value;
            paused_changed ();
        }
        get { return _paused; }
    }

    public signal void clock_started ();
    public signal void paused_changed ();
    public signal void tick ();

    public signal void redraw_sector (uint x, uint y);

    public signal void marks_changed ();
    public signal void explode ();
    public signal void cleared ();

    public Minefield (uint width, uint height, uint n_mines)
    {
        locations = new Location[width, height];
        for (var x = 0; x < width; x++)
            for (var y = 0; y < height; y++)
                locations[x, y] = new Location ();
        this.width = width;
        this.height = height;
        this.n_mines = n_mines;
    }

    public bool is_clock_started ()
    {
        return elapsed > 0;
    }
   
    public bool has_mine (uint x, uint y)
    {
        return locations[x, y].has_mine;
    }

    public bool is_cleared (uint x, uint y)
    {
        return locations[x, y].cleared;
    }

    public bool is_location (int x, int y)
    {
        return x >= 0 && y >= 0 && x < width && y < height;
    }

    public void clear_mine (uint x, uint y)
    {
        if (!exploded)
            start_clock ();

        /* Place mines on first attempt to clear */
        if (!placed_mines)
        {
            place_mines (x, y);
            placed_mines = true;
        }

        if (locations[x, y].cleared || locations[x, y].flag == FlagType.FLAG)
            return;

        clear_mines_recursive (x, y);

        /* Failed if this contained a mine */
        if (locations[x, y].has_mine)
        {
            if (!exploded)
            {
                exploded = true;
                stop_clock ();
                explode ();
            }
            return;
        }

        /* Mark unmarked mines when won */
        if (is_complete)
        {
            stop_clock ();
            for (var tx = 0; tx < width; tx++)
                for (var ty = 0; ty < height; ty++)
                    if (has_mine (tx, ty))
                        set_flag (tx, ty, FlagType.FLAG);
            cleared ();
        }
    }

    private void clear_mines_recursive (uint x, uint y)
    {
        /* Ignore if already cleared */
        if (locations[x, y].cleared)
            return;

        locations[x, y].cleared = true;
        n_cleared++;
        if (locations[x, y].flag == FlagType.FLAG)
            n_flags--;
        locations[x, y].flag = FlagType.NONE;
        redraw_sector (x, y);
        marks_changed ();

        /* Automatically clear locations if no adjacent mines */
        if (!locations[x, y].has_mine && get_n_adjacent_mines (x, y) == 0)
        {
            foreach (var neighbour in neighbour_map)
            {
                var nx = (int) x + neighbour.x;
                var ny = (int) y + neighbour.y;
                if (is_location (nx, ny))
                    clear_mines_recursive (nx, ny);
            }
        }
    }

    public void set_flag (uint x, uint y, FlagType flag)
    {
        if (locations[x, y].cleared || locations[x, y].flag == flag)
            return;

        if (flag == FlagType.FLAG)
            n_flags++;
        else if (locations[x, y].flag == FlagType.FLAG)
            n_flags--;

        locations[x, y].flag = flag;
        redraw_sector (x, y);

        /* Update warnings */
        /* FIXME: Doesn't check if have changed, just if might have changed */
        foreach (var neighbour in neighbour_map)
        {
            var nx = (int) x + neighbour.x;
            var ny = (int) y + neighbour.y;
            if (is_location (nx, ny) && is_cleared (nx, ny))
                redraw_sector (nx, ny);
        }

        marks_changed ();
    }
    
    public FlagType get_flag (uint x, uint y)
    {
        return locations[x, y].flag;
    }

    public uint get_n_adjacent_mines (uint x, uint y)
    {
        uint n = 0;
        foreach (var neighbour in neighbour_map)
        {
            var nx = (int) x + neighbour.x;
            var ny = (int) y + neighbour.y;
            if (is_location (nx, ny) && has_mine (nx, ny))
                n++;
        }
        return n;
    }

    public bool has_flag_warning (uint x, uint y)
    {
        if (!is_cleared (x, y))
            return false;

        uint n_mines = 0, n_flags = 0;
        foreach (var neighbour in neighbour_map)
        {
            var nx = (int) x + neighbour.x;
            var ny = (int) y + neighbour.y;
            if (!is_location (nx, ny))
                continue;
            if (has_mine (nx, ny))
                n_mines++;
            if (get_flag (nx, ny) == FlagType.FLAG)
                n_flags++;
        }

        return n_flags > n_mines;
    }

    /* Randomly set the mines, but avoid the current and adjacent locations */
    private void place_mines (uint x, uint y)
    {
        for (var n = 0; n < n_mines;)
        {
            var rx = Random.int_range (0, (int32) width);
            var ry = Random.int_range (0, (int32) height);
            
            if (rx == x && ry == y)
                continue;

            if (!locations[rx, ry].has_mine)
            {
                var adj_found = false;

                foreach (var neighbour in neighbour_map)
                {
                    if (rx == x + neighbour.x && ry == y + neighbour.y)
                    {
                        adj_found = true;
                        break;
                    }
                }

                if (!adj_found)
                {
                    locations[rx, ry].has_mine = true;
                    n++;
                }
            }
        }
    }

    private void start_clock ()
    {
        if (clock == null)
            clock = new Timer ();
        clock_started ();
        timeout_cb ();
    }

    private void stop_clock ()
    {
        if (clock == null)
            return;
        if (clock_timeout != 0)
            Source.remove (clock_timeout);
        clock_timeout = 0;
        clock.stop ();
        tick ();
    }

    private void continue_clock ()
    {
        if (clock == null)
            clock = new Timer ();
        else
            clock.continue ();
        timeout_cb ();
    }

    private bool timeout_cb ()
    {
        /* Notify on the next tick */
        var elapsed = clock.elapsed ();
        var next = (int) (elapsed + 1.0);
        var wait = next - elapsed;
        clock_timeout = Timeout.add ((int) (wait * 1000), timeout_cb);

        tick ();

        return false;
    }
}
