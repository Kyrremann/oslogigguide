const ogg_url = "https://oslogigguide.kyrremann.no";
const calendar_url = "https://raw.githubusercontent.com/Kyrremann/oslogigguide/refs/heads/main/_data/calendars.json";

var user = localStorage.getItem("user")
var token = localStorage.getItem("token")
if (user && token) {
	document.getElementById("user").value = user;
	document.getElementById("token").value = token;
	load();
}

async function load() {
	var user = document.getElementById("user").value;
	var token = document.getElementById("token").value;
	if (!user || !token) {
		alert("Please enter both user and token.");
		return;
	}
	localStorage.setItem("user", user);
	localStorage.setItem("token", token);

	const calendars = await getData();
	if (calendars[user]) {
		calendars[user].forEach(item => {
			console.log(`ID: ${item.id}, Name: ${item.name}`);
			star(item.id);
		}
		);
	}
}

async function getData() {
	try {
		const response = await fetch(calendar_url);
		if (!response.ok) {
			throw new Error(`Response status: ${response.status}`);
		}

		const result = await response.json();

		return result;
	} catch (error) {
		console.error(error.message);
	}
}

async function star(id) {
	const element = document.getElementById(id);
	element.classList.add('starred');
	element.onclick = unsubscribe;
}

async function unstar(id) {
	const element = document.getElementById(id);
	element.classList.remove('starred');
	element.onclick = subscribe;
}

async function subscribe(event) {
	const calendarId = event.target.id;
	const user = document.getElementById("user").value;
	const token = document.getElementById("token").value;
	const name = event.target.getAttribute("data-name");
	console.log(`Subscribing ${name} to calendar owned by ${user}`);

	const payload = {
		id: calendarId,
		user: user,
		token: token,
		name: name,
	};
	try {
		const response = await fetch(ogg_url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json'
			},
			body: JSON.stringify(payload)
		});
		if (!response.ok) {
			throw new Error(`Response status: ${response.status}`);
		}

		const result = await response.json();
		console.log(result);
		star(calendarId);
	}
	catch (error) {
		console.error(error.message);
	}
}

async function unsubscribe(event) {
	const calendarId = event.target.id;
	const user = document.getElementById("user").value;
	const token = document.getElementById("token").value;
	console.log(`Unsubscribing ${calendarId} from calendar owned by ${user}`);

	const payload = {
		id: calendarId,
		user: user,
		token: token,
	};
	try {
		const response = await fetch(ogg_url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json'
			},
			body: JSON.stringify(payload)
		});
		if (!response.ok) {
			throw new Error(`Response status: ${response.status}`);
		}

		const result = await response.json();
		console.log(result);
		unstar(calendarId);
	}
	catch (error) {
		console.error(error.message);
	}
}
