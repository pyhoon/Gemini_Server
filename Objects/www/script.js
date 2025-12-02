let currentAiMessage = null;
let currentEventSource = null;
let jsonBuffer = '';

// Set initial timestamp
document.getElementById('initialTimestamp').textContent = new Date().toLocaleTimeString();

function sendMessage() {
    const userInput = document.getElementById('userInput');
    const sendButton = document.getElementById('sendButton');
    const message = userInput.value.trim();

    if (!message) return;

    // Disable input during request
    userInput.disabled = true;
    sendButton.disabled = true;

    // Add user message to chat
    addMessage(message, 'user');
    userInput.value = '';

    // Show typing indicator
    const typingIndicator = document.getElementById('typingIndicator');
    typingIndicator.style.display = 'block';
    scrollToBottom();

    // Create empty AI message container
    currentAiMessage = addMessage('', 'ai');

    let fullResponse = '';
    let receivedComplete = false;

    // Close any existing connection
    if (currentEventSource) {
        currentEventSource.close();
    }

    // Reset buffer
    jsonBuffer = '';

    console.log('Starting EventSource connection...');

    // Use EventSource for simpler SSE handling
    currentEventSource = new EventSource('/gemini?data=' + encodeURIComponent(JSON.stringify({
        prompt: message
    })));

    currentEventSource.onopen = function (event) {
        console.log('SSE Connection opened successfully');
    };

    currentEventSource.onmessage = function (event) {
        console.log('Raw SSE data received:', event.data);

        // Add to buffer
        jsonBuffer += event.data;

        // Try to parse complete JSON objects from the buffer
        processBuffer();
    };

    function processBuffer() {
        let startIndex = 0;
        let braceCount = 0;
        let bracketCount = 0;
        let inString = false;
        let escapeNext = false;

        for (let i = 0; i < jsonBuffer.length; i++) {
            const char = jsonBuffer[i];

            if (escapeNext) {
                escapeNext = false;
                continue;
            }

            if (char === '\\') {
                escapeNext = true;
                continue;
            }

            if (char === '"' && !escapeNext) {
                inString = !inString;
                continue;
            }

            if (!inString) {
                if (char === '{') braceCount++;
                if (char === '}') braceCount--;
                if (char === '[') bracketCount++;
                if (char === ']') bracketCount--;
            }

            // Check if we have a complete JSON structure
            if ((braceCount === 0 && bracketCount === 0) && (char === '}' || char === ']')) {
                const completeJson = jsonBuffer.substring(startIndex, i + 1);
                startIndex = i + 1;

                if (completeJson.trim()) {
                    try {
                        const data = JSON.parse(completeJson);
                        console.log('Successfully parsed JSON:', data);
                        processData(data);
                    } catch (e) {
                        console.error('Failed to parse complete JSON:', completeJson, e);
                    }
                }
            }
        }

        // Keep the remaining incomplete data in the buffer
        jsonBuffer = jsonBuffer.substring(startIndex);
    }

    function processData(data) {
        if (data.error) {
            console.error('Server error:', data.error);
            currentAiMessage.querySelector('.message-content').textContent = 'Error: ' + data.error;
            currentAiMessage.classList.add('error-message');
            completeRequest();
            return;
        }

        if (data.content) {
            fullResponse += data.content;
            currentAiMessage.querySelector('.message-content').textContent = fullResponse;
            scrollToBottom();
            console.log('Updated response, length:', fullResponse.length);
        }

        if (data.status === 'complete') {
            console.log('Received completion signal');
            receivedComplete = true;
            completeRequest();
        }
    }

    currentEventSource.onerror = function (event) {
        console.log('SSE connection error or closed');
        if (!receivedComplete && !fullResponse) {
            currentAiMessage.querySelector('.message-content').textContent =
                'Connection interrupted. Please try again.';
            currentAiMessage.classList.add('error-message');
        }
        completeRequest();
    };

    function completeRequest() {
        console.log('Completing request, full response received:', fullResponse.length > 0);
        if (currentEventSource) {
            currentEventSource.close();
            currentEventSource = null;
        }
        typingIndicator.style.display = 'none';
        if (currentAiMessage && fullResponse) {
            addTimestamp(currentAiMessage);
        }
        userInput.disabled = false;
        sendButton.disabled = false;
        userInput.focus();
        currentAiMessage = null;
        jsonBuffer = '';
    }

    // Set timeout to complete request after 30 seconds
    setTimeout(() => {
        if (currentEventSource && !receivedComplete) {
            console.log('Request timeout after 30 seconds');
            if (!fullResponse) {
                currentAiMessage.querySelector('.message-content').textContent =
                    'Request timed out. Please try again.';
                currentAiMessage.classList.add('error-message');
            }
            completeRequest();
        }
    }, 60000);
}

function addMessage(content, type) {
    const chatMessages = document.getElementById('chatMessages');
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}-message`;

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    contentDiv.textContent = content;

    messageDiv.appendChild(contentDiv);
    chatMessages.appendChild(messageDiv);

    scrollToBottom();
    return messageDiv;
}

function addTimestamp(messageElement) {
    const timestamp = document.createElement('div');
    timestamp.className = 'timestamp';
    timestamp.textContent = new Date().toLocaleTimeString();
    messageElement.appendChild(timestamp);
}

function scrollToBottom() {
    const chatMessages = document.getElementById('chatMessages');
    setTimeout(() => {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }, 100);
}

// Handle Enter key
document.getElementById('userInput').addEventListener('keypress', function (e) {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

// Auto-focus input
document.getElementById('userInput').focus();