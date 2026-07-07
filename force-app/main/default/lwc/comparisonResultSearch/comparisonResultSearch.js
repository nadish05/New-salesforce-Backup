import { LightningElement, api, track } from 'lwc';

import getComparisonResults
from '@salesforce/apex/ComparisonResultController.getComparisonResults';

import getResultCount
from '@salesforce/apex/ComparisonResultController.getResultCount';

const COLUMNS = [
    {
        label: 'Comparison Result Name',
        fieldName: 'recordUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: {
                fieldName: 'Name'
            },
            target: '_blank'
        }
    }
];

export default class ComparisonResultSearch extends LightningElement {

    @api recordId;

    @track results = [];

    columns = COLUMNS;

    searchKey = '';

    pageSize = 50;
    pageNumber = 1;

    totalCount = 0;

    sortBy = 'Name';
    sortDirection = 'asc';

    delayTimeout;

    connectedCallback() {
        this.loadData();
    }

    get cardTitle() {
        return `Comparison Results (${this.totalCount})`;
    }

    get disablePrevious() {
        return this.pageNumber === 1;
    }

    get disableNext() {
        return this.pageNumber * this.pageSize >= this.totalCount;
    }

    loadData() {

        getResultCount({
            metadataComparisonId: this.recordId,
            searchKey: this.searchKey
        })
        .then(count => {
            this.totalCount = count;
        });

        getComparisonResults({
            metadataComparisonId: this.recordId,
            searchKey: this.searchKey,
            pageSize: this.pageSize,
            pageNumber: this.pageNumber,
            sortField: this.sortBy,
            sortDirection: this.sortDirection.toUpperCase()
        })
        .then(data => {

            this.results = data.map(row => {
                return {
                    ...row,
                    recordUrl: '/' + row.Id
                };
            });

        })
        .catch(error => {
            console.error(error);
        });
    }

    handleSearch(event) {

        const value = event.target.value;

        clearTimeout(this.delayTimeout);

        this.delayTimeout = setTimeout(() => {

            this.searchKey = value;
            this.pageNumber = 1;

            this.loadData();

        }, 300);
    }

    handleSort(event) {

        this.sortBy = 'Name';
        this.sortDirection = event.detail.sortDirection;

        this.loadData();
    }

    handleNext() {

        this.pageNumber++;

        this.loadData();
    }

    handlePrevious() {

        if(this.pageNumber > 1) {

            this.pageNumber--;

            this.loadData();
        }
    }
}