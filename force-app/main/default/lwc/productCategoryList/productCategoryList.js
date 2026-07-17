import { LightningElement, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import PRODUCT_CATEGORY_FIELD from '@salesforce/schema/Opportunity.Product_Category__c'; // adjust API name

export default class ProductCategoryList extends LightningElement {

    recordTypeId;
    categories;

    @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    objectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValues, { 
        recordTypeId: '$recordTypeId', 
        fieldApiName: PRODUCT_CATEGORY_FIELD 
    })
    picklistHandler({ data, error }) {
        if (data) {
            this.categories = data.values;
        } else if (error) {
            console.error(error);
        }
    }
}