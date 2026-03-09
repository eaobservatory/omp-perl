$(document).ready(function () {
    var side_menu = $('div#layout_side_bar');

    var show_side_menu = (function (show) {
        if (show) {
            side_menu.removeClass('hide_menu');
            side_menu.addClass('show_menu');
        } else {
            side_menu.removeClass('show_menu');
            side_menu.addClass('hide_menu');
        }
    });

    $('a#layout_side_show_hide').click(function () {
        if (side_menu.hasClass('hide_menu') || ! side_menu.hasClass('show_menu')) {
            show_side_menu(true);
        } else {
            show_side_menu(false);
        }
    });

    $('#layout_side_close a').click(function() {
        show_side_menu(false);
    });

    $('#layout_side_reopen a').click(function() {
        show_side_menu(true);
    });
});
