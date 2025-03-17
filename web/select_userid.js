$(document).ready(function () {
    var user_select = $('select[name=userid]');

    $.ajax(user_select.data('userlist'), dataType='json').done(function (result) {
        settings = {
            'options': result,
            'allowEmptyOption': true,
            'showEmptyOptionInDropdown': true,
            'emptyOptionLabel': '',
            'searchField': ['text', 'value']
        };

        var selected_value = user_select.data('selected');
        if (selected_value !== '') {
            settings['items'] = [selected_value];
        }

        user_select.children().detach();
        user_select.selectize(settings);

    }).fail(function (jqXHR, textStatus) {
        user_select.children().detach();
        user_select.append($('<option/>', {'text': 'Failed to load user list.', 'value': ''}));
    });
});
