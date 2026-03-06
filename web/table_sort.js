$(document).ready(function () {
    $('table.sortable').each(function () {
        var table = $(this);
        var sort_headings = table.find('thead').find('th.sortable, td.sortable');
        var table_body = table.find('tbody').first();
        var last_sorted_by = null;
        var sort_direction = -1;

        var apply_sort_column = (function (sort_key) {
            var arr = [];
            var i;

            last_sorted_by = sort_key;

            table.prev('.index-title-key').css('visibility', 'hidden');
            table_body.children('tr.index-title').remove();

            table_body.children('tr').each(function () {
                arr.push({row: this, value: $(this).data('sortinfo')[sort_key]});
            });

            arr.sort(function (a, b) {
                if (a.value === b.value) {
                    return 0;
                }
                if (a.value === null && b.value !== null) {
                    return 1;
                }
                if (b.value === null && a.value !== null) {
                    return -1;
                }
                return (sort_direction * (a.value < b.value ? -1 : 1));
            });

            for (i in arr) {
                table_body.append($(arr[i].row).detach());
            }

            sort_direction = - sort_direction;

            sort_headings.removeClass('sorted_asc').addClass('sortable');
            sort_headings.removeClass('sorted_desc').addClass('sortable');
            sort_headings.each(function () {
                var heading = $(this);
                if (heading.data('sortkey') === sort_key) {
                    heading.removeClass('sortable').addClass((sort_direction < 0 ) ? 'sorted_asc' : 'sorted_desc');
                }
            });
        });

        sort_headings.each(function () {
            var heading = $(this);

            var sort_key = heading.data('sortkey');
            var default_sort_order = 1;

            if (heading.hasClass('sortreverse')) {
                default_sort_order = -1;
            }

            if (heading.hasClass('sortedalready')) {
                last_sorted_by = sort_key;
            }

            heading.click(function () {
                if (sort_key !== last_sorted_by) {
                    sort_direction = default_sort_order;
                }

                apply_sort_column(sort_key);
            });
        });
    });
});
