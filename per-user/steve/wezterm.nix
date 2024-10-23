{...}: {
  programs.wezterm = {
    enable = true;

    extraConfig = ''
      local c = wezterm.config_builder()

      function scheme_for_appearance(appearance)
        if appearance:find 'Dark' then
          return 'Catppuccin Mocha'
        else
          return 'Catppuccin Latte'
        end
      end

      wezterm.plugin.require('https://github.com/nekowinston/wezterm-bar').apply_to_config(c, {
        position = 'bottom',
        max_width = 32,
        dividers = 'slant_right',
        indicator = {
          leader = {
            enabled = true,
            off = ' ',
            on = ' ',
          },
          mode = {
            enabled = true,
            names = {
              resize_mode = 'RESIZE',
              copy_mode = 'VISUAL',
              search_mode = 'SEARCH',
            },
          },
        },
        tabs = {
          numerals = 'arabic',
          pane_count = 'subscript',
          brackets = {
            active = { "", ':' },
            inactive = { "", ':' },
          },
        },
        clock = {
          enabled = true,
          format = '%l:%M %p',
        },
      })

      local config = {
        adjust_window_size_when_changing_font_size = false,
        color_scheme = scheme_for_appearance(wezterm.gui.get_appearance()),
        cursor_blink_ease_in = 'Constant',
        cursor_blink_ease_out = 'Constant',
        cursor_blink_rate = 500,
        default_cursor_style = 'BlinkingBar',
        enable_scroll_bar = false,
        font = wezterm.font_with_fallback ({
          {family='JetBrains Mono'},
          {family='Fira Code'},
        }),
        font_size = 12,
        front_end = 'WebGpu',
        hide_tab_bar_if_only_one_tab = true,
        macos_window_background_blur = 32,
        use_fancy_tab_bar = false,
        webgpu_power_preference = 'HighPerformance',
        window_background_opacity = 0.85,
        window_decorations = 'RESIZE',
        window_padding = { left = 1, right = 0, top = 0, bottom = 0 },

        window_frame = {
          border_left_width = '0.5cell',
          border_right_width = '0.1cell',
          border_top_height = '0.1cell',
          border_bottom_height = '0.1cell',

          border_left_color = '#404040',
          border_right_color = '#404040',
          border_top_color = '#404040',
          border_bottom_color = '#404040'
        }
      }

      for k, v in pairs(config) do
        c[k] = v
      end

      return c
    '';
  };
}
