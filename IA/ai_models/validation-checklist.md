# End-to-End Validation Checklist

Use this checklist after deploying the separated AI runtime architecture.

## Pre-validation setup

- [ ] Frappe `bench migrate` completed
- [ ] Frappe `bench clear-cache` completed
- [ ] AI runtime server running and healthy (`GET /health` returns 200)
- [ ] Frappe configured with `Model Provider = Internal AI API`
- [ ] `Internal AI API Base URL` pointing to the AI runtime server
- [ ] `Internal AI Model` set to an available model on the AI server

## Core inference paths

### CV extraction
- [ ] Upload a single CV PDF/DOCX through the batch queue interface
- [ ] Verify CV is processed and extracted data appears
- [ ] Verify candidate profile is created
- [ ] Verify analysis log entry is created with tokens

### Contract inconsistency
- [ ] Open `Find Contract Inconsistencies` page
- [ ] Select a customer
- [ ] Upload a contract file
- [ ] Click `Analyze Contract`
- [ ] Verify result appears
- [ ] Verify history entry is saved
- [ ] Verify analysis log entry is created with tokens

### Requirements compliance
- [ ] Open `Analyze Against User Requirements` page
- [ ] Select a customer
- [ ] Enter requirements text
- [ ] Upload a document file
- [ ] Click `Analyze Requirements`
- [ ] Verify result appears
- [ ] Verify history entry is saved
- [ ] Verify analysis log entry is created with tokens

### AI Agent chat
- [ ] Open chat interface
- [ ] Send a message that requires model inference
- [ ] Verify response appears
- [ ] Verify tokens are logged

## Batch CV processing

- [ ] Create a new CV batch
- [ ] Upload multiple PDF files
- [ ] Start the batch analysis
- [ ] Verify each file is processed
- [ ] Verify progress updates in the queue panel
- [ ] Verify results populate the live results table

## History and reopening

- [ ] Reopen a previous CV batch from history
- [ ] Verify the batch queue reloads correctly
- [ ] Verify results table reloads correctly
- [ ] Reopen a previous contract review from history
- [ ] Verify the review result is displayed
- [ ] Reopen a previous requirements review from history
- [ ] Verify the review result is displayed

## Compatibility

- [ ] Decision Tree mode still works unchanged
- [ ] Hybrid `AI Agent + Decision Tree` still works
- [ ] Switching provider back to Ollama still works (legacy compatibility)

## Audit and logging

- [ ] Open `Chatbot Analysis Log`
- [ ] Verify all new analysis transactions are visible
- [ ] Verify `prompt_tokens` and `completion_tokens` are populated
- [ ] Verify `total_tokens` equals prompt + completion
- [ ] Verify `analysis_type` matches the actual analysis type
- [ ] Verify `batch_id` is populated for batch-processed CV items
- [ ] Verify `customer`, `file_name`, `user_name`, `ip_address` are populated

## Error handling

- [ ] Stop the AI runtime server and attempt an analysis
- [ ] Verify a clear error message is shown (not a raw traceback)
- [ ] Restart the AI runtime server
- [ ] Verify analysis works again without Frappe restart

## Configuration UI

- [ ] Open `Chatbot Settings`
- [ ] Verify `Internal AI API` is the default provider
- [ ] Verify legacy Ollama sections are marked as such
- [ ] Open `Chatbot Analysis Settings`
- [ ] Verify same configuration behavior

## Frontend

- [ ] All pages load without errors
- [ ] Sidebar navigation works for all sections
- [ ] No console errors on page load
- [ ] Page reload restores only active processing batches (not completed ones)
