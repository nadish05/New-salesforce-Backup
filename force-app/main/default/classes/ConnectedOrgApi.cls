@RestResource(urlMapping='/connectedorg/*')
global with sharing class ConnectedOrgApi {

    // =========================================
    // SAVE CONNECTED ORG
    // =========================================

    @HttpPost
    global static String saveOrg() {

        try {

            RestRequest req =
                RestContext.request;

            String body =
                req.requestBody.toString();

            Map<String, Object> data =

                (Map<String, Object>)
                JSON.deserializeUntyped(body);

            String orgId =

                (String)data.get('orgId');

            String orgName =

                (String)data.get('orgName');

            String instanceUrl =

                (String)data.get('instanceUrl');

            String refreshToken =

                (String)data.get('refreshToken');

            String environment =

                (String)data.get('environment');

            // =====================================
            // Save Connected Org
            // =====================================

            Id recordId =
                ConnectedOrgService.saveConnectedOrg(

                    orgId,

                    orgName,

                    instanceUrl,

                    refreshToken,

                    environment

                );

            return JSON.serialize(

                new Map<String, Object>{

                    'success' => true,

                    'recordId' => recordId

                }

            );

        } catch (Exception e) {

            RestContext.response.statusCode = 500;

            return JSON.serialize(

                new Map<String, Object>{

                    'success' => false,

                    'message' => e.getMessage()

                }

            );

        }

    }

}