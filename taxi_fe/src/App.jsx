import { useState } from 'react'
import './App.css'
import Customer from './components/Customer';
import Driver from './components/Driver';

function App() {
  return (
    <div className="App">
      <Customer username="juanpablo"/>
      <Driver username="frodo"/>
      <Driver username="pippin"/>
      <Driver username="samwise"/>
    </div>
  )
}

export default App