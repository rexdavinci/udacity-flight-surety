
import DOM from './dom';
import Contract from './contract';
import './flightsurety.css';

let contract
(async() => {

    let result = null;

    contract = new Contract('localhost', () => {
        operational()
        registerAirline()

        // User-submitted transaction
        DOM.elid('submit-oracle').addEventListener('click', () => {
            let flight = DOM.elid('flight-number').value;
            // Write transaction
            contract.fetchFlightStatus(flight, (error, result) => {
                display('Oracles', 'Trigger oracles', [ { label: 'Fetch Flight Status', error: error, value: result.flight + ' ' + result.timestamp} ]);
            });
        })
    
    });
})();

function operational() {
    contract.isOperational((error, result) => {
        console.log(error,result);
        display('Operational Status', 'Check if contract is operational', [ { label: 'Operational Status', error: error, value: result} ]);
    });
}

function registerAirline() {
    DOM.elid('add-flight').addEventListener('click', () => {
        let flight = DOM.elid('add-flight-number').value;
        contract.registerFlight(flight, (error, result) => {
            console.log(error, result)
        })
    })
}


function display(title, description, results) {
    let displayDiv = DOM.elid("display-wrapper");
    let section = DOM.section();
    section.appendChild(DOM.h2(title));
    section.appendChild(DOM.h5(description));
    results.map((result) => {
        let row = section.appendChild(DOM.div({className:'row'}));
        row.appendChild(DOM.div({className: 'col-sm-4 field'}, result.label));
        row.appendChild(DOM.div({className: 'col-sm-8 field-value'}, result.error ? String(result.error) : String(result.value)));
        section.appendChild(row);
    })
    displayDiv.append(section);

}







