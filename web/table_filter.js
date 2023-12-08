$(document).ready(function () {
    $('.table_filter').each(function () {
        var filter = $(this);
        var filter_boxes = filter.find('input[type=checkbox]');

        var tableid = filter.data('table');
        var table = $('table#' + tableid);

        var parameter = filter.data('parameter');

        var filter_table = (function () {
            var enabled = [];
            filter_boxes.each(function () {
                var box = $(this);
                if (box.prop('checked')) {
                    enabled.push(box.data(parameter));
                }
            });

            table.find('tr').each(function () {
                var row = $(this);
                var parameters = row.data(parameter);
                if (parameters !== undefined) {
                    if (enabled.some(function (element, index, array) {return parameters[element];})) {
                        row.show();
                    } else {
                        row.hide();
                    }
                }
            });
        });

        filter_boxes.each(function () {
            $(this).change(filter_table);
        });

        filter_table();
    });
});
