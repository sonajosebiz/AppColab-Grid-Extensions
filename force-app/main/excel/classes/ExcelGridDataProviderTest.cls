@IsTest
private class ExcelGridDataProviderTest {

    private static String sampleUsedRangeJson() {
        return '{' +
            '"address":"Sheet1!A1:C3",' +
            '"values":[' +
                '["Name","Amount","Email"],' +
                '["Acme Corp",1500,"info@acme.com"],' +
                '["Beta LLC",2500,"contact@beta.com"]' +
            ']' +
        '}';
    }

    @IsTest
    static void getCapabilities_buildsColumnsFromHeaders() {
        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, capabilities);
        System.assertEquals(4, capabilities.columns.size()); // Id + 3 headers
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('DELETE'));

        Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition> colMap = new Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            colMap.put(col.id, col);
        }
        System.assert(colMap.containsKey('Id'));
        System.assert(colMap.containsKey('Name'));
        System.assert(colMap.containsKey('Amount'));
        System.assert(colMap.containsKey('Email'));
        System.assertEquals(false, colMap.get('Id').visible);
    }

    @IsTest
    static void getData_returnsParsedRecords() {
        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('2', result.records[0].get('Id'));
        System.assertEquals('Acme Corp', result.records[0].get('Name'));
        System.assertEquals(1500, result.records[0].get('Amount'));
    }

    @IsTest
    static void getData_withSearch_filtersRecords() {
        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.searchTerm = 'Beta';
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, result);
        System.assertEquals(1, result.records.size());
        System.assertEquals('Beta LLC', result.records[0].get('Name'));
    }

    @IsTest
    static void saveRecords_updatesExistingAndAppendsNew() {
        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Map<String, Object> existingRow = new Map<String, Object>{
            'Id' => '2',
            'Name' => 'Acme Updated',
            'Amount' => 1800,
            'Email' => 'info@acme.com'
        };
        Map<String, Object> newRow = new Map<String, Object>{
            'Id' => 'TEMP_1',
            'Name' => 'Gamma Inc',
            'Amount' => 3000,
            'Email' => 'gamma@example.com'
        };
        request.records = new List<Map<String, Object>>{ existingRow, newRow };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult saveRes = provider.saveRecords(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, saveRes);
        System.assertEquals(2, saveRes.records.size());
        System.assertEquals('4', newRow.get('Id')); // Appended after row 3
    }

    @IsTest
    static void deleteRecords_deletesSpecifiedRows() {
        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.recordIds = new List<String>{ '2', '3' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, mock.lastMethod);
    }

    @IsTest
    static void resolveParentMatchValue_withContact_returnsId() {
        Contact c = new Contact(LastName = 'ExcelTest');
        insert c;

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = c.Id;

        ExcelGridDataProvider.ExcelConfig cfg = new ExcelGridDataProvider.ExcelConfig();
        cfg.parentMatchField = 'Id';

        String val = ExcelGridDataProvider.resolveParentMatchValue(cfg, ctx);
        System.assertEquals(c.Id, val);
    }

    @IsTest
    static void helperMethods_extractHeadersAndColumns() {
        List<Object> row1 = new List<Object>{ 'ColA', 'ColB' };
        List<Object> allRows = new List<Object>{ row1 };
        List<String> headers = ExcelGridDataProvider.extractHeaders(allRows, 1);
        System.assertEquals(2, headers.size());
        System.assertEquals('ColA', headers[0]);

        System.assertEquals('A', ExcelGridDataProvider.getColumnLetter(1));
        System.assertEquals('Z', ExcelGridDataProvider.getColumnLetter(26));
        System.assertEquals('AA', ExcelGridDataProvider.getColumnLetter(27));
    }
    private static ExcelTestSupport.RecordingMock arrange(String configJson, String body) {
        ExcelGridDataProvider.testGridDef = new appcg__Grid_Definition__c(appcg__Data_Provider_Config__c = configJson);
        ExcelTestSupport.RecordingMock mock = new ExcelTestSupport.RecordingMock(body);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static appcg.GridDataProviderTypesV1.QueryRequest queryRequest(String parentId) {
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.context.parentId = parentId;
        request.pageSize = 10;
        return request;
    }

    private static appcg.GridDataProviderTypesV1.SaveRequest saveRequest(List<Map<String, Object>> records, String parentId) {
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = queryRequest(parentId).context;
        request.records = records;
        return request;
    }

    private static appcg.GridDataProviderTypesV1.DeleteRequest deleteRequest(List<String> rowIds) {
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = queryRequest(null).context;
        request.recordIds = rowIds;
        return request;
    }

    @IsTest
    static void offsetUsedRange_preservesWorksheetPositions() {
        ExcelTestSupport.RecordingMock mock = arrange('{"filePath":"/Documents/Sales.xlsx","headerRow":3}',
            '{"rowIndex":2,"columnIndex":2,"values":[["Name","Amount"],["Acme",100],["",null],["Beta",200]]}');
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(queryRequest(null));
        System.assertEquals(2, page.records.size());
        System.assertEquals('4', page.records[0].get('Id'));
        System.assertEquals('6', page.records[1].get('Id'));
        provider.saveRecords(saveRequest(new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '4', 'Name' => 'Updated' },
            new Map<String, Object>{ 'Id' => 'TEMP_a', 'Name' => 'New', 'Amount' => 300 },
            new Map<String, Object>{ 'Name' => 'More' }
        }, null));
        System.assert(mock.requests[2].getEndpoint().contains('C4%3AD4'), mock.requests[2].getEndpoint());
        Map<String, Object> patchBody = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[2].getBody());
        List<Object> values = (List<Object>) patchBody.get('values');
        System.assertEquals(null, ((List<Object>) values[0])[1], 'Omitted cell must be preserved');
        System.assert(mock.requests[3].getEndpoint().contains('C7%3AD8'), mock.requests[3].getEndpoint());
        provider.deleteRecords(deleteRequest(new List<String>{ '4', '6', '4' }));
        System.assertEquals(7, mock.requests.size());
        System.assert(mock.requests[5].getEndpoint().contains('C6%3AD6'));
        System.assert(mock.requests[6].getEndpoint().contains('C4%3AD4'));
    }

    @IsTest
    static void headers_areUniqueAndDoNotReplaceRowIds() {
        arrange('{"workbookId":"wb123"}', '{"values":[["Id","Name","name","", "Column4"],["external-id","A","B","C","D"]]}');
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = queryRequest(null);
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(request.context);
        System.assertEquals(6, caps.columns.size());
        System.assertEquals('Id_2', caps.columns[1].id);
        System.assertEquals('name_2', caps.columns[3].id);
        System.assertEquals('Column4_2', caps.columns[5].id);
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        System.assertEquals('2', page.records[0].get('Id'));
        System.assertEquals('external-id', page.records[0].get('Id_2'));
    }

    @IsTest
    static void cache_isConsumedAndKeyedToConfigurationAndParent() {
        ExcelTestSupport.RecordingMock mock = arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = queryRequest(null);
        provider.getCapabilities(request.context);
        provider.getData(request);
        System.assertEquals(1, mock.requests.size());
        provider.getData(request);
        System.assertEquals(2, mock.requests.size(), 'Refresh must re-read');
        provider.getCapabilities(request.context);
        ExcelGridDataProvider.testGridDef.appcg__Data_Provider_Config__c = '{"workbookId":"another"}';
        provider.getData(request);
        System.assertEquals(4, mock.requests.size());
        System.assert(mock.requests[3].getEndpoint().contains('/items/another/'));
        provider.getCapabilities(request.context);
        provider.getData(queryRequest('003000000000001AAA'));
        System.assertEquals(6, mock.requests.size());
    }

    @IsTest
    static void parentMatching_filtersAndPopulatesNewRows() {
        Contact parent = new Contact(LastName = 'Excel', Email = 'parent@example.com');
        insert parent;
        Test.startTest();
        ExcelTestSupport.RecordingMock mock = arrange(
            '{"workbookId":"wb123","parentMatchColumn":"Email","parentMatchField":"Email","autoPopulateParent":true}',
            '{"values":[["Name","Email"],["Match","parent@example.com"],["Other","other@example.com"]]}');
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(queryRequest(parent.Id).context);
        System.assertEquals(true, caps.columns[2].isReadOnly);
        System.assertEquals(1, provider.getData(queryRequest(parent.Id)).records.size());
        Map<String, Object> newRow = new Map<String, Object>{ 'Name' => 'New' };
        provider.saveRecords(saveRequest(new List<Map<String, Object>>{ newRow }, parent.Id));
        System.assertEquals('4', newRow.get('Id'));
        System.assertEquals(parent.Email, newRow.get('Email'));
        System.assert(mock.requests[2].getBody().contains(parent.Email));
        try {
            provider.saveRecords(saveRequest(new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => '3', 'Name' => 'Unauthorized' } }, parent.Id));
            System.assert(false, 'Unmatched parent row must be rejected');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('editable data row'));
        }
        try {
            provider.saveRecords(saveRequest(new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => '2', 'Email' => 'other@example.com' } }, parent.Id));
            System.assert(false, 'Locked parent column must be rejected');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('read-only'));
        }
        System.assertEquals(5, mock.requests.size(), 'Rejected saves may read, but must not write');
        Test.stopTest();
    }

    @IsTest
    static void parentMatching_accepts15CharacterIds() {
        String parentId = '003000000000001AAA';
        arrange('{"workbookId":"wb123","parentMatchColumn":"Parent"}',
            '{"values":[["Name","Parent"],["Match","003000000000001"],["Other","003000000000002"]]}');
        appcg.GridDataProviderTypesV1.PageResult page = new ExcelGridDataProvider().getData(queryRequest(parentId));
        System.assertEquals(1, page.records.size());
        System.assertEquals('Match', page.records[0].get('Name'));
    }

    @IsTest
    static void blankParentField_returnsNoRowsAndRejectsAutoPopulation() {
        Contact parent = new Contact(LastName = 'No email');
        insert parent;
        Test.startTest();
        ExcelTestSupport.RecordingMock mock = arrange(
            '{"workbookId":"wb123","parentMatchColumn":"Email","parentMatchField":"Email","autoPopulateParent":true}', sampleUsedRangeJson());
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        System.assertEquals(0, provider.getData(queryRequest(parent.Id)).records.size());
        try {
            provider.saveRecords(saveRequest(new List<Map<String, Object>>{ new Map<String, Object>{ 'Name' => 'New' } }, parent.Id));
            System.assert(false, 'Blank parent field must be rejected');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('no value for Email'));
        }
        System.assertEquals(2, mock.requests.size());
        Test.stopTest();
    }

    @IsTest
    static void invalidParentColumnAndField_areReported() {
        Contact parent = new Contact(LastName = 'Excel');
        insert parent;
        Test.startTest();
        arrange('{"workbookId":"wb123","parentMatchColumn":"Missing"}', sampleUsedRangeJson());
        try {
            new ExcelGridDataProvider().getData(queryRequest(parent.Id));
            System.assert(false, 'Missing column must fail');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('was not found'));
        }
        ExcelGridDataProvider.testGridDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","parentMatchColumn":"Name","parentMatchField":"NotAField"}';
        try {
            new ExcelGridDataProvider().getData(queryRequest(parent.Id));
            System.assert(false, 'Missing field must fail');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('does not exist'));
        }
        Test.stopTest();
    }

    @IsTest
    static void mutations_invalidateCapabilitiesCache() {
        ExcelTestSupport.RecordingMock mock = arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        provider.getCapabilities(queryRequest(null).context);
        provider.saveRecords(saveRequest(new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => '2', 'Name' => 'Updated' } }, null));
        mock.usedRangeBody = '{"values":[["Name","Amount","Email"],["Updated",1500,"info@acme.com"]]}';
        System.assertEquals('Updated', provider.getData(queryRequest(null)).records[0].get('Name'));
        System.assertEquals(4, mock.requests.size());
        provider.getCapabilities(queryRequest(null).context);
        provider.deleteRecords(deleteRequest(new List<String>{ '2' }));
        mock.usedRangeBody = '{"values":[["Name","Amount","Email"]]}';
        System.assertEquals(0, provider.getData(queryRequest(null)).records.size());
        System.assertEquals(8, mock.requests.size());
    }

    @IsTest
    static void invalidMutationIds_areRejectedBeforeWrites() {
        ExcelTestSupport.RecordingMock mock = arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        for (String invalidId : new List<String>{ '1', '4', 'x', '-1', '0' }) {
            try {
                provider.deleteRecords(deleteRequest(new List<String>{ '2', invalidId }));
                System.assert(false, 'Invalid deletion must fail: ' + invalidId);
            } catch (ExcelGridDataProvider.ProviderException e) {
                System.assert(e.getMessage().contains('editable data row'));
            }
        }
        try {
            provider.saveRecords(saveRequest(new List<Map<String, Object>>{
                new Map<String, Object>{ 'Id' => '2', 'Name' => 'Updated' },
                new Map<String, Object>{ 'Id' => '1', 'Name' => 'Header' }
            }, null));
            System.assert(false, 'Invalid edit must fail');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('editable data row'));
        }
        System.assertEquals(6, mock.requests.size());
        for (HttpRequest request : mock.requests) System.assertEquals('GET', request.getMethod());
    }

    @IsTest
    static void failedAppend_doesNotAssignRowIds() {
        ExcelTestSupport.RecordingMock mock = arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        mock.failWriteStatus = 403;
        Map<String, Object> record = new Map<String, Object>{ 'Id' => 'TEMP_1', 'Name' => 'New' };
        try {
            new ExcelGridDataProvider().saveRecords(saveRequest(new List<Map<String, Object>>{ record }, null));
            System.assert(false, 'Expected write failure');
        } catch (ExcelClient.HttpException e) {
            System.assert(e.getMessage().contains('HTTP 403'));
        }
        System.assertEquals('TEMP_1', record.get('Id'));
    }

    @IsTest
    static void limits_applyAfterSearchAndParentFiltering() {
        arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        ExcelGridDataProvider.testGridDef.appcg__Pagination_Type__c = 'Client-Side';
        ExcelGridDataProvider.testGridDef.appcg__Record_Limit__c = 1;
        appcg.GridDataProviderTypesV1.QueryRequest request = queryRequest(null);
        request.searchTerm = 'BETA';
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        System.assertEquals(1, page.records.size());
        System.assertEquals('Beta LLC', page.records[0].get('Name'));
        request.searchTerm = null;
        System.assertEquals(1, provider.getData(request).totalCount);
        ExcelGridDataProvider.testGridDef.appcg__Pagination_Type__c = null;
        ExcelGridDataProvider.testGridDef.appcg__Record_Limit__c = 10;
        ExcelGridDataProvider.testGridDef.appcg__Page_Size__c = '1';
        request.pageSize = 0;
        System.assertEquals(1, provider.getData(request).records.size());
    }

    @IsTest
    static void blankWorksheet_returnsNoRowsAndRejectsWrites() {
        arrange('{"workbookId":"wb123"}', '{"rowIndex":0,"columnIndex":0,"values":[[""]]}');
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        System.assertEquals(0, provider.getData(queryRequest(null)).records.size());
        System.assertEquals(1, provider.getCapabilities(queryRequest(null).context).columns.size());
        try {
            provider.saveRecords(saveRequest(new List<Map<String, Object>>{ new Map<String, Object>{ 'Name' => 'New' } }, null));
            System.assert(false, 'A worksheet needs headers before writing');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('header row'));
        }
    }

    @IsTest
    static void invalidConfigs_haveClearErrors() {
        for (String configJson : new List<String>{ null, '', '{', 'null', '{}', '{"workbookId":"wb","headerRow":0}', '{"workbookId":"wb","autoPopulateParent":true}' }) {
            ExcelGridDataProvider.testGridDef = new appcg__Grid_Definition__c(appcg__Data_Provider_Config__c = configJson);
            try {
                ExcelGridDataProvider.parseConfig(queryRequest(null).context);
                System.assert(false, 'Invalid config must fail: ' + configJson);
            } catch (ExcelGridDataProvider.ProviderException e) {
                System.assert(String.isNotBlank(e.getMessage()));
            }
        }
        ExcelGridDataProvider.testGridDef = null;
        System.assertEquals(null, ExcelGridDataProvider.getGridDefinition(null));
    }

    @IsTest
    static void emptyRequests_doNotCallOut() {
        ExcelTestSupport.RecordingMock mock = arrange('{"workbookId":"wb123"}', sampleUsedRangeJson());
        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        System.assertEquals(0, provider.saveRecords(saveRequest(null, null)).records.size());
        provider.deleteRecords(null);
        provider.deleteRecords(deleteRequest(new List<String>()));
        System.assertEquals(0, mock.requests.size());
        try {
            provider.getData(null);
            System.assert(false, 'Null query must fail');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('query request'));
        }
        try {
            provider.saveRecords(null);
            System.assert(false, 'Null save must fail');
        } catch (ExcelGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('save request'));
        }
    }

    @IsTest
    static void helpers_handleEmptySparseAndTypedCells() {
        System.assertEquals(0, ExcelGridDataProvider.extractHeaders(null, 1).size());
        System.assertEquals(0, ExcelGridDataProvider.extractHeaders(new List<Object>{ null }, 1).size());
        System.assertEquals(0, ExcelGridDataProvider.parseDataRows(null, new List<String>{ 'Name' }, 1).size());
        System.assertEquals('BOOLEAN', ExcelGridDataProvider.inferFieldType('Flag', new List<Map<String, Object>>{ new Map<String, Object>{ 'Flag' => true } }));
        System.assertEquals('TEXT', ExcelGridDataProvider.inferFieldType('Flag', null));
        System.assertEquals('TEXT', ExcelGridDataProvider.inferFieldType('Flag', new List<Map<String, Object>>{ new Map<String, Object>{ 'Flag' => 'plain' } }));
        System.assertEquals('XFD', ExcelGridDataProvider.getColumnLetter(16384));
    }
}
