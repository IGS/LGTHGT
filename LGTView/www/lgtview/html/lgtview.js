Ext.Loader.setPath('Ext.ux', 'ux');
Ext.Loader.setConfig({enabled: true});

Ext.onReady(function(){
     var conf = {
        db: 'lgtview_example',
        host: '172.18.0.1:27017',
        site: 'http://localhost:8080/twinblast.html'
    };
    var allStores = [];
    var portlets = {
        0 : [],
        1: []};

    var get_metadata = 0;
    Ext.regModel('gene',{
    });

    var offset = 0;

// START CHART SECTION
    addWindow({'name': 'euk_genus',
               'title': 'Euk Genus',
               'modname': 'euk_genus'
              });

    addWindow({'name': 'euk_ref',
               'title': 'Eukaryote Mappings',
               'modname': 'euk_ref'});

    addWindow({'name': 'bac_genus',
               'title': 'Bac Genus',
               'modname': 'bac_genus'});
// END CHART SECTION

    // Curation is an integral component, always include
    addWindow({'name': 'curation_note',
               'title': 'Curation Note',
               'modname': 'curation_note'
              });

    Ext.regModel('filters',{
        fields: [
            {name: 'key',type: 'string'},
            {name: 'value', type: 'string'},
            {name: 'op', type: 'string'}
        ]
    });

    var filterstore = new Ext.data.Store({
        model: 'filters',
        proxy: {
            type: 'memory',
            reader: {
                type: 'json',
                root: 'loads'
            }
        }
    });    

    var cellEditing = Ext.create('Ext.grid.plugin.CellEditing', {
        clicksToEdit: 1
    });

    var filtergrid = new Ext.grid.Panel({
        store: filterstore,
        forcefit: true,
        anchor: '100%, 100%',
        flex: 1,
        selModel: {
            selType: 'cellmodel'
        },
        plugins: [cellEditing],
        columns: [
            {text: 'Key', dataIndex: 'key', type: 'string',width: 80},
            {header: 'Op',
            dataIndex: 'op',
            width: 60,
            field: {
                xtype: 'combobox',
                typeAhead: true,
                triggerAction: 'all',
                selectOnTab: true,
                store: [
                    ['=','eq'],
                    ['!=','ne']
                ],
                lazyRender: true,
                listClass: 'x-combo-list-small'
            }},
            {text: 'value', dataIndex: 'value', type: 'string', width:80, editor: {xtype: 'textfield'}},

            {xtype: 'actioncolumn',
                width: 20,
                items: [{
                    icon   : 'delete.gif',  // Use a URL in the icon config
                    tooltip: 'Remove filter',
                    handler: function(grid, rowIndex, colIndex) {
                        var rec = filterstore.getAt(rowIndex);
                        filterstore.remove(rec);
                        loadData();
                    }
                }]
            }
        ]
    });

// START FILTER SECTION 1
    var min_euk_len = new Ext.form.field.Text({
        fieldLabel: 'min euk length',
        value: 15,
        name: 'min_euk_len'
    });
    var min_bac_len = new Ext.form.field.Text({
        fieldLabel: 'min bac length',
        value: 15,
        name: 'min_bac_len'
    });
    var chosen_euk_genus = new Ext.form.field.Text({
        fieldLabel: 'eukaryote genus',
        name: 'chosen_euk_genus'
    });
    var chosen_bac_genus = new Ext.form.field.Text({
        fieldLabel: 'bacteria genus',
        name: 'chosen_bac_genus'
    });
    var filterform = new Ext.form.Panel({
        width: '100%',
        height: '100%',
        frame: true,
        items: [min_euk_len,min_bac_len,chosen_euk_genus,chosen_bac_genus]
    });
// END FILTER SECTION 1

    Ext.regModel('reads',{
    });

    var readgrid;
    var configured = false;
    var metadataMenu = Ext.create('Ext.menu.Menu');

    var readstore = new Ext.data.Store({
        model: 'reads',
        storeId: 'reads',
        pageSize: 100,
        proxy: {
            type: 'ajax',
            timeout: 5000000,
            url: '/cgi-bin/view.cgi',
            extraParams: {
                'db': conf.db,
                'host': conf.host
            },
            reader: {
                type: 'json',
                root: 'retval'
            }
        },
        listeners: {
            metachange : function(store,meta) {
                if(!configured && meta != undefined) {
                    Ext.each(meta.columns, function(col) {
                        if(col.dataIndex =='read') {
                            col.renderer = function(value,p,record) {
                                return '<a target=_blank href=' + conf.site + '#?id='+
                                    value+
                                    '&file=example_blastn.out>'+
                                    value+
                                    '</a>';
                            }
                        }

                        // Excluding both the MongoDB generated ID as well as any metadata that
                        // follows the naming convention like bac_*. This is because it would not
                        // make much sense to plot the bac data against the bac_blast_lca (default
                        // Y-axis), e.g. plotting bac_blast_lca v bac_genus. 
                        if(col.dataIndex != '_id' && col.dataIndex.search(/bac\_/) == -1) {

                            var md = Ext.create('Ext.Action', {
                                text:  col.dataIndex,
                                handler: function() {
                                    var prev_md = Ext.ComponentQuery.query('#metadata')[0];
                                    prev_md.setText(col.dataIndex);
                                }
                            }); 

                            metadataMenu.add(md);
                        }
                    }); // End iteration over metadata columns

                    readgrid.reconfigure(store,meta.columns);
                    configured = true;
                }
            }
        }
    });
    
    readgrid = new Ext.grid.Panel({
        store: readstore,
        title: 'Reads',
        region: 'south',
        forcefit: true,
        height: 250,
        split: true,
        columns: [],
        // paging bar on the bottom
        bbar: Ext.create('Ext.PagingToolbar', {
            store: readstore,
            displayInfo: true,
            displayMsg: 'Displaying reads {0} - {1} of {2}',
            emptyMsg: "No reads to display"
        }),
    });

    var krona_plot = Ext.create('Ext.Action', {
        text: 'Krona',
        handler: function() {
            var pm = Ext.ComponentQuery.query('#plot_menu')[0];
            var ct = Ext.ComponentQuery.query('#config_tb')[0];
            pm.setText('Krona');
            ct.hide();
        }
    });

    var hm_plot = Ext.create('Ext.Action', {
        text: 'heatmap',
        handler: function() {
            var pm = Ext.ComponentQuery.query('#plot_menu')[0];
            var ct = Ext.ComponentQuery.query('#config_tb')[0];
            pm.setText('heatmap');
            ct.show();
        }
    });

    var bacwin = new Ext.Panel({
        title: 'Bacterial Mappings',
        layout: 'fit',
        split: true,
        region: 'east',
        flex: 1,
        autoScroll: true,
        dockedItems: [
            {
            xtype: 'toolbar',
            dock: 'top',
            items: [
                {
                xtype: 'label',
                html: "Plot Configuration"
                },{
                xtype: 'tbspacer',
                flex: 1
                },{
                text: 'Krona',
                id: 'plot_menu',
                menu: [krona_plot, hm_plot]
                },{
                xtype: 'tbspacer',
                flex: 1
                },{
                text: 'Load Plot',
                handler: function() {
                    alert('hi');
                }
                }
            ]
            },{
            xtype: 'toolbar',
            dock: 'top',
            id: 'config_tb',
            hidden: true,
            items: [
                {
                xtype: 'label',
                html: 'Taxonomic Rank:'
                },{
                xtype: 'textfield',
                id: 'tax_rank',
                value: 3,
                width: 24
                },'-',
                {
                xtype: 'label',
                html: 'Column Limit:'
                },{
                xtype: 'textfield',
                id: 'limit',
                value: 30,
                width: 24
                },'-',
                {
                xtype: 'label',
                html: 'Abundance Type:'
                },{
                text: 'relative',
                id: 'abundance_type',
                handler: function() {
                    if(this.getText() == 'relative'){
                        this.setText('absolute');
                    } else {
                        this.setText('relative');
                    }
                }
                },'-',
                {
                xtype: 'label',
                html: 'Metadata:'
                },{
                text: 'metadata',
                id: 'metadata',
                menu: metadataMenu
                }
            ]
            }
        ],
        loader: {
            loadMask: false
        },
        items: [{
            xtype : 'component',
            id    : 'bac-iframe',
            autoEl : {
                tag : "iframe",
            }
        }]
    });

    var titlebar = new Ext.Panel({
	height: 54,
        region: 'north',
        forcefit: true,
        layout: 'hbox',
        items: [
        {width: 260,
        xtype: 'container',
        html: '<img height=50px src=lgtview_logo_50px_trans.png>'},
        {width: 800,
        xtype: 'container',
        padding: '10 0 5 10',
	html: '<i>The reads below are putative Lateral Gene Transfer reads. They are paired-end reads where one mate maps to a donor genome and the other mate maps to a host genome. Clicking on the pie charts will filter the reads in the display. Selecting/deselecting elements from the \'filters\' section will also change the reads in the display. Clicking on a read name in the \'read\' column will open a page with BLAST results for that read.</i>'},
        {flex: 1,xtype: 'container'}
        ]
    });

    // Dynamically generate graph selection menu
    var graphMenu = Ext.create('Ext.menu.Menu'); 
    makeGraphMenu(portlets[0]);
    makeGraphMenu(portlets[1]);

    // Now remove pie charts that the user no longer wants.
    // Current implementation only removes, does not add (which 
    // requires a call to view.cgi). User can start fresh 
    // by clicking reload in the Filters panel.
    var graphs_reload = Ext.create('Ext.Action', {
        text: 'Remove Marked Graphs',
        handler: function() {
            graphMenu.items.each(function(item) {

                var removed = false;

                // Only need to process if one is to be hidden
                if(item.iconCls == 'hide'){

                    // Unfortunately, with subsequent deletions, will throw 
                    // off the ability to do simple checks to know which portlet
                    // the chart resides in. Just iterate over both until found. 
                    if(removed == false) {

                        removed = removePieChart(item, portlets[0]);
                    }
                    if(removed == false) {

                        removed = removePieChart(item, portlets[1]);
                    }

                    // Until reloading these pie charts is possible, prevent 
                    // interaction with the field button but show what was removed
                    item.disable(); 
                }
            }); // menu iterator
        } // handler
    });

    var vp = new Ext.Viewport({
        items: [titlebar,
            {xtype: 'portalpanel',
             id: 'portalpanel',
             region: 'center',
             title: 'Graphs',
             dockedItems: {
                 itemId: 'graphs_toolbar',
                 xtype: 'toolbar',
                 dock: 'top',
                 items: [
                     {
                         text: 'Select Graphs to Keep',
                         menu: graphMenu
                     },{
                         xtype:'tbspacer',
                         flex:1
                     },
                     graphs_reload
                 ]
             },
             items: [{
                 items: portlets[0]
             },{
                 items: portlets[1]
             }]
            },readgrid,
            bacwin,
            {layout: 'fit',
            region: 'west',
            title: 'Filters',
            buttons: [{text: 'reload',handler: function() { loadData()}},
                     {text: 'tab-delimited',handler: function() { getText('dl')}}],
            split: true,
            items: [{layout: 'anchor',
                     items: [
                         filterform,
                         filtergrid]
                    }],
             width: 275}],
        layout: 'border',

    });

    allStores.push(readstore);
    var allfilters = {};
    loadData();

    function getFilters() {

        allfilters = {};

        filterstore.each(function(rec) {
            var val = rec.data.value;
            if(rec.data.op == '=') {
                allfilters[rec.data.key] = val;
            }
            else if(rec.data.op == '!=') {
                allfilters[rec.data.key] = {'$ne': val};
            }
        });

// START FILTER SECTION 2
        if(min_euk_len.getValue() != '') {
            allfilters['euk_len'] = {'$gt': min_euk_len.getValue()*1};
        }
        if(min_bac_len.getValue() != '') {
            allfilters['bac_len'] = {'$gt': min_bac_len.getValue()*1};
        }
        if(min_euk_len.getValue() != '') {
            allfilters['euk_genus'] = {'$regex': chosen_euk_genus.getValue()};
        }
        if(min_euk_len.getValue() != '') {
            allfilters['bac_genus'] = {'$regex': chosen_bac_genus.getValue()};
        }
// END FILTER SECTION 2


        return allfilters;
    }

    // Will generate a menu of actions that tie to whether or not 
    // the particular pie graph is to be included in the display.
    function makeGraphMenu(portlet_array) {

        for (var i = 0; i < portlet_array.length; ++i) {

            var cls = 'show';
            Ext.util.CSS.createStyleSheet('.show {background-image: url(http://famfamfam.com/lab/icons/silk/icons/accept.png);} .hide {background-image: url(http://famfamfam.com/lab/icons/silk/icons/cancel.png);}');

            var my_portlet = '' + i + portlet_array[i];

            var my_portlet = Ext.create('Ext.Action', {
                iconCls: 'show',
                text: portlet_array[i].title,
                hideOnClick: false,
                handler: function() {
                    cls = cls == 'show' ? 'hide' : 'show';
                    this.setIconCls(cls);
                }
            });

            graphMenu.add(my_portlet);
        }
    }

    // Function to eliminate the portlet pie chart displays one at a time
    function removePieChart(meta_item, portlet_array) {

        var found = false;

        for (var i = 0; i < portlet_array.length; ++i) {

            if(meta_item.text == portlet_array[i].title){
                var m_id = '#' + portlet_array[i].title;
                var pc = Ext.ComponentQuery.query(m_id)[0];
                pc.destroy();
                portlet_array.splice(i,1); // need to reformat array
                found = true;
                break;
            }
        }

        if(found) {return true;} else {return false;}
    }

    function getText(out_type) {

        var filters = getFilters();
        var params;

        if(out_type == 'dl') {
            params = {
                cond: Ext.encode(filters),
                file_format: out_type,
                format: 'text'
            }
        }

        else if(out_type == 'local') {
            var vals = hm_form.getValues();
            params = {
                cond: Ext.encode(filters),
                file_format: out_type,
                format: 'text',
                infile: vals.inp_infile,
                tax_rank: vals.inp_tax_rank,
                chosen_metadata: vals.inp_chosen_metadata,
                abudance_type: vals.inp_abundance_type
            }
        }

        Ext.apply(params,conf);
        var request = Ext.urlEncode(params);
        if (!Ext.fly('frmDummy')) {
            var frm = document.createElement('form');
            frm.id = 'frmDummy';
            frm.name = frm.id;
            frm.className = 'x-hidden';
            document.body.appendChild(frm);
        }

        Ext.Ajax.request({
            method: 'POST',
            timeout: 5000000,
            isUpload: true,
            form: Ext.fly('frmDummy'),
            url: '/cgi-bin/view.cgi',
            params: params,
            success: function(response){
                var res = Ext.decode(response.responseText);
                Ext.getDom('bac-iframe').src = res.file;
            }
        });
    }

    function loadData(caller,cond) {
        appendFilter(cond);
        allfilters = {};
        filterstore.each(function(rec) {
            if(rec.data.op == '=') {
                allfilters[rec.data.key] = rec.data.value;
            }
            else if(rec.data.op == '!=') {
                allfilters[rec.data.key] = {'$ne': rec.data.value};
            }
        });

// START FILTER SECTION 2
        if(min_euk_len.getValue() != '') {
            allfilters['euk_len'] = {'$gt': min_euk_len.getValue()*1};
        }
        if(min_bac_len.getValue() != '') {
            allfilters['bac_len'] = {'$gt': min_bac_len.getValue()*1};
        }
        if(chosen_euk_genus.getValue() != '') {
            allfilters['euk_genus'] = {'$regex': chosen_euk_genus.getValue()};
        }
        if(chosen_bac_genus.getValue() != '') {
            allfilters['bac_genus'] = {'$regex': chosen_bac_genus.getValue()};
        }
// END FILTER SECTION 2

        // Reload the Krona Plot here
        var kronaparams = {
            cond: Ext.encode(allfilters),
            format: 'krona',
            condfield: 'bac_blast_lca'
        }
        Ext.apply(kronaparams,conf);
        Ext.Ajax.request({
            url: '/cgi-bin/view.cgi',
            params: kronaparams,
            success: function(response){
                var res = Ext.decode(response.responseText);
                Ext.getDom('bac-iframe').src = res.file;
            }
        });
        
        var read_storage = Ext.getStore('reads');
        Ext.each(allStores, function(store) {
       
                // Right here, need to make a decision for whether or not
                // the user has chosen to remove this data from the current
                // instance. If the user has, stop CGI calls. 
                var exclude = false;

                // First need to do a check for whether this store is a pie
                // chart or not. Only do removal check if pie chart.
                if(store != read_storage) {

                    // This menu often won't be that large, OK to just iterate
                    // over instead of adding in more attributes for querying.
                    graphMenu.items.each(function(item) {

                        var curr_pie = Ext.getStore(item.text);
                        if(store == curr_pie) {

                            if(item.iconCls == 'hide'){
                                exclude = true;
                            }
                        }
                    });

                    if(exclude != true) {

                        Ext.apply(store.getProxy().extraParams,
                            {cond: Ext.encode(allfilters),
                        });
                        store.load();
                    }
                }
                else {
                    Ext.apply(store.getProxy().extraParams,
                        {cond: Ext.encode(allfilters),
                    });
                    store.load();
                }
        });
    }
    
    function appendFilter(filter) { 
        for(i in filter) if (filter.hasOwnProperty(i)) {
            if(filterstore.findRecord('key',i)) {
                var rec = filterstore.findRecord('key',i);
                rec.set('value',filter[i]);
                rec.set('op', '=');
            }
            else {
                filterstore.add({
                    'key': i,
                    'op': '=',
                    'value': filter[i]
                });
            }
        }
    }

    function addWindow(params) {

        Ext.regModel(params.modname,{
        fields: [
            {mapping: '_id',name: params.name,type: 'string'},
            {name: 'count', type: 'int'}
        ]
        });

        var newstore = new Ext.data.Store({
            model: params.modname,
            storeId: params.modname,
            autoLoad: false,
            proxy: {
                type: 'ajax',
                url: '/cgi-bin/view.cgi',
                extraParams: {
                    'criteria': params.name,
                    'db': conf.db,
                    'host': conf.host,
                },
                reader: {
                    type: 'json',
                    root: 'retval'
                }
            }
        });

        var newchart = new Ext.chart.Chart({
            animate: true,
            store: newstore,
            shadow: false,
            legend: {
                position: 'right'
            },
            theme: 'Base:gradients',
            series: [{
                type: 'pie',
                field: 'count',
                listeners: {

                    'itemmouseup': function(item) {
                        var newparams = [];
                        newparams[params.name] = item.storeItem.data[params.name];
                        loadData(newstore,newparams);
                    }
                },
                tips: {
                    width: 250,
                    renderer: function(storeItem, item) {
                        var title = 'Unknown';
                        if(storeItem.get(params.name)) {
                            title = storeItem.get(params.name);
                        }
                        this.setTitle(title+'<br/>'+storeItem.get('count')+' reads');
                    }
                },
                highlight: {
                    segment: {
                        margin:20
                    }
                },
                label: {
                    field: params.name,
                    display: 'rotate',
                    contrast: true
                }
            }]
        });

        allStores.push(newstore);
        if(portlets[0].length <= portlets[1].length) {
            portlets[0].push({title: '' + params.name,
                              height: 200,
                              id: '' + params.name,
                              items: newchart});
        }
        else {
            portlets[1].push({title: '' + params.name,
                              height: 200,
                              id: '' + params.name,
                              items: newchart});
        }
        
        offset = offset + 50;
    }
});
