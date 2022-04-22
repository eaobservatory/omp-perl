$(document).ready(function () {
    var filter_box = $('[name="user_filter"]');
    filter_box.keyup(function () {
        var filter = filter_box.val().toLowerCase();
        var rows = $('table#user_table').find('tr');
        if (filter === '') {
            rows.show();
            rows.not('.index-title').filter(':nth-child(even)').attr('class', 'row_clear');
            rows.not('.index-title').filter(':nth-child(odd)').attr('class', 'row_shaded');
        } else {
            var i = 0;
            rows.not(':first').each(function () {
                var row = $(this);
                if (row.hasClass('index-title')) {
                    row.hide();
                } else {
                    if (row.data('query').indexOf(filter) === -1) {
                        row.hide();
                    } else {
                        row.show();
                        row.attr('class', (i ++ % 2) ? 'row_shaded' : 'row_clear');
                    }
                }
            });
        }
    });
});
